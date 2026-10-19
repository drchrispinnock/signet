// Shielded tez (TzEL): what Swift calls for a shield. Everything crosses the bridge as hex
// strings or plain JSON; the protocol work is in tzel.js. Two kinds of export live here:
//
//   * the layer 1 deposit to the TzEL bridge ticketer (`mint`), an ordinary approved, locally
//     signed transaction like the Etherlink deposit in bridge.js;
//   * pure helpers over the wallet's secrets: key derivation for an address, deposit-pool ids,
//     the note scan, the shield witness and its kernel-wire encoding. The auth tree itself is
//     built natively (XMSSAuthTree.swift); Swift hands the sibling path in and the witness
//     builder checks it against the address's root before signing.
//
// Every export is async so that a refusal rejects the promise and reaches Swift as the error
// text (the bridge turns a synchronous throw into "no result"). Secrets reach these functions
// the way a tz secret key reaches a signing call: per call, for the one job, never kept. Scanning gets the viewing material (`incoming_seed`, `nk`) only; the
// signing seed (`ask_j`) and `outgoing_seed` come in for the shield alone.

import { TezosToolkit } from "@taquito/taquito";
import { signerFor, readOnlySigner } from "./signers.js";
import { approvedEstimate, sendApproved, parseLimits } from "./operations.js";
import {
  AUTH_TREE_SIZE, FELT_BYTES, acceptsNote, authLeaf, authRootFromPath, buildOutputNote, bytesToHex, decodeEncryptedNote, decodePublishedNote, decryptMemo, depositBalanceKey, depositBlind, depositPubkeyHash, depositRecipient, deriveAccount, deriveAsk, deriveAuthPubSeed, deriveDiversifier, deriveNkSpend, deriveNkTag, detect, encodeEncryptedNote, encodeShieldMessage, feltOfInt, hexToBytes, kemDetectSeed, kemKeygen, kemViewSeed, memoText, nullifier, paymentAddressFromJSON, shieldSighash, shieldWitness, wotsSign,
} from "./tzel.js";

const hex = bytesToHex;
const bytes = (h, what, length) => {
  if (typeof h !== "string" || !/^([0-9a-fA-F]{2})*$/.test(h)) throw new Error(`tzel: ${what} must be hex`);
  const out = hexToBytes(h.toLowerCase());
  if (length !== undefined && out.length !== length) throw new Error(`tzel: ${what} must be ${length} bytes`);
  return out;
};
const feltIn = (h, what) => bytes(h, what, FELT_BYTES);

function mutez(value, what) {
  const text = String(value);
  if (!/^\d{1,20}$/.test(text)) throw new Error(`tzel: ${what} must be a whole number of mutez`);
  const n = BigInt(text);
  if (n > 0xffffffffffffffffn) throw new Error(`tzel: ${what} does not fit a u64`);
  return n;
}

// ---- Layer 1 deposit ----------------------------------------------------------------------------

/** `mint (pair (bytes %receiver) (address %rollup))` with the tez attached: the ticketer sends the rollup a ticket for `deposit:<pool>`. */
export async function shieldDepositParams(ticketer, rollup, pubkeyHashHex, amountMutez) {
  if (!/^KT1[1-9A-HJ-NP-Za-km-z]{33}$/.test(ticketer)) throw new Error(`Not a bridge ticketer contract: ${ticketer}`);
  if (!/^sr1[1-9A-HJ-NP-Za-km-z]{33}$/.test(rollup)) throw new Error(`Not a Smart Rollup address: ${rollup}`);
  const amount = mutez(amountMutez, "deposit amount");
  if (amount === 0n) throw new Error("A deposit of 0 tez is refused by the ticketer");
  const recipient = depositRecipient(feltIn(pubkeyHashHex, "pubkey_hash"));
  return {
    to: ticketer,
    amount: Number(amount),
    mutez: true,
    parameter: { entrypoint: "mint", value: { prim: "Pair", args: [{ bytes: hex(new TextEncoder().encode(recipient)) }, { string: rollup }] } },
  };
}

/** Fee, burn and limits for depositing `amountMutez` from `source` into pool `pubkeyHashHex`. */
export async function estimateShieldDeposit(rpcUrl, source, publicKey, ticketer, rollup, pubkeyHashHex, amountMutez) {
  const params = await shieldDepositParams(ticketer, rollup, pubkeyHashHex, amountMutez);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  return approvedEstimate(tk, "transaction", params, await tk.estimate.transfer(params));
}

/** Signs and injects the deposit with exactly the approved limits (S14); `{ hash, injected, signedBytes }` (S15). */
export async function sendShieldDeposit(rpcUrl, signerSpec, ticketer, rollup, pubkeyHashHex, amountMutez, limitsJson) {
  const params = await shieldDepositParams(ticketer, rollup, pubkeyHashHex, amountMutez);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  return sendApproved(tk, rpcUrl, "transaction", params, parseLimits(limitsJson));
}

// ---- Keys ---------------------------------------------------------------------------------------

/** The four account seeds of a master key (hex in, hex out). */
export async function tzelAccount(masterSkHex) {
  const a = deriveAccount(feltIn(masterSkHex, "master_sk"));
  return { nk: hex(a.nk), askBase: hex(a.askBase), incomingSeed: hex(a.incomingSeed), outgoingSeed: hex(a.outgoingSeed) };
}

/**
 * Everything address `j` needs except its auth root, which comes from the native tree build:
 * the diversifier, nullifier tag, the two ML-KEM public keys, the signing seed `ask_j` and its
 * public seed. The caller keeps `askJ` with the master key, never in the address record.
 */
export async function tzelAddressKeys(accountJson, j) {
  const account = typeof accountJson === "string" ? JSON.parse(accountJson) : accountJson;
  if (!Number.isInteger(j) || j < 0 || j > 0xffffffff) throw new Error("tzel: address index must be a u32");
  const incomingSeed = feltIn(account.incomingSeed, "incoming_seed");
  const nk = feltIn(account.nk, "nk");
  const askJ = deriveAsk(feltIn(account.askBase, "ask_base"), j);
  const dJ = deriveDiversifier(incomingSeed, j);
  const ekV = kemKeygen(kemViewSeed(incomingSeed, j)).ek;
  const ekD = kemKeygen(kemDetectSeed(incomingSeed, j)).ek;
  return { index: j, dJ: hex(dJ), nkTag: hex(deriveNkTag(deriveNkSpend(nk, dJ))), ekV: hex(ekV), ekD: hex(ekD), askJ: hex(askJ), pubSeed: hex(deriveAuthPubSeed(askJ)) };
}

/** The WOTS+ leaf of key `keyIdx` (for checking the native tree builder against this module). */
export async function tzelAuthLeaf(askJHex, pubSeedHex, keyIdx) {
  return hex(authLeaf(feltIn(askJHex, "ask_j"), feltIn(pubSeedHex, "pub_seed"), keyIdx));
}

/** A new deposit pool for address `addressIndex` under `nonce`: its blind, id, L1 recipient string and durable balance key. */
export async function tzelDepositPool(masterSkHex, addressIndex, nonce, authDomainHex, authRootHex, pubSeedHex) {
  const blind = depositBlind(feltIn(masterSkHex, "master_sk"), addressIndex, mutez(nonce, "deposit nonce"));
  const pubkeyHash = depositPubkeyHash(feltIn(authDomainHex, "auth_domain"), feltIn(authRootHex, "auth_root"), feltIn(pubSeedHex, "pub_seed"), blind);
  return { blind: hex(blind), pubkeyHash: hex(pubkeyHash), recipient: depositRecipient(pubkeyHash), balanceKey: depositBalanceKey(pubkeyHash) };
}

// ---- Scan ---------------------------------------------------------------------------------------

function addressRecord(a) {
  return { index: a.index, dJ: feltIn(a.dJ, "d_j"), authRoot: feltIn(a.authRoot, "auth_root"), pubSeed: feltIn(a.pubSeed, "pub_seed"), nkTag: feltIn(a.nkTag, "nk_tag") };
}

/**
 * Which of `notes` (`[{ index, bytes }]`, published-note records as hex) belong to one of our
 * `addresses`: detect, decrypt, then accept only when the commitment recomputed from our address
 * record matches. Returns `[{ index, cm, v, rseed, addressIndex, nullifier }]` (mutez as text).
 */
export async function tzelScan(accountJson, addressesJson, notesJson) {
  const account = typeof accountJson === "string" ? JSON.parse(accountJson) : accountJson;
  const addresses = (typeof addressesJson === "string" ? JSON.parse(addressesJson) : addressesJson).map(addressRecord);
  const notes = typeof notesJson === "string" ? JSON.parse(notesJson) : notesJson;
  const incomingSeed = feltIn(account.incomingSeed, "incoming_seed");
  const nk = feltIn(account.nk, "nk");
  const keys = addresses.map((a) => ({
    address: a,
    dkV: kemKeygen(kemViewSeed(incomingSeed, a.index)).dk,
    dkD: kemKeygen(kemDetectSeed(incomingSeed, a.index)).dk,
    nkSpend: deriveNkSpend(nk, a.dJ),
  }));
  const found = [];
  for (const note of notes) {
    if (!Number.isInteger(note.index) || note.index < 0) throw new Error("tzel: note index must be a whole number");
    const { cm, enc } = decodePublishedNote(bytes(note.bytes, `note ${note.index}`));
    for (const k of keys) {
      if (!detect(enc, k.dkD)) continue;
      const opened = decryptMemo(enc, k.dkV);
      if (!opened || !acceptsNote(k.address, cm, opened)) continue;
      found.push({ index: note.index, cm: hex(cm), v: opened.v.toString(10), rseed: hex(opened.rseed), addressIndex: k.address.index, nullifier: hex(nullifier(k.nkSpend, cm, note.index)), memo: memoText(opened.memo) });
      break;
    }
  }
  return found;
}

// ---- Shield -------------------------------------------------------------------------------------

/**
 * Builds a shield of `v` mutez from pool `pubkeyHash`, paying `fee` to the rollup and
 * `producerFee` to the DAL producer at `producerAddress` (the reference JSON form): the two
 * output notes, the sighash, the WOTS+ signature with key `keyIdx` and the Cairo witness. The
 * caller has already persisted `keyIdx` as used. Refuses a pool id or auth path that does not
 * match the address, so a stale record never produces a proof the kernel would reject.
 */
export async function tzelBuildShield(json) {
  const p = typeof json === "string" ? JSON.parse(json) : json;
  const askJ = feltIn(p.askJ, "ask_j");
  const outgoingSeed = feltIn(p.outgoingSeed, "outgoing_seed");
  const address = { ...addressRecord(p.address), ekV: bytes(p.address.ekV, "ek_v", 1184), ekD: bytes(p.address.ekD, "ek_d", 1184) };
  const producer = paymentAddressFromJSON(p.producerAddress);
  const authDomain = feltIn(p.authDomain, "auth_domain");
  const pubkeyHash = feltIn(p.pubkeyHash, "pubkey_hash");
  const blind = feltIn(p.blind, "blind");
  const v = mutez(p.v, "shield value"), fee = mutez(p.fee, "fee"), producerFee = mutez(p.producerFee, "producer fee");
  if (producerFee === 0n) throw new Error("tzel: the producer fee must be positive");
  const keyIdx = p.keyIdx;
  if (!Number.isInteger(keyIdx) || keyIdx < 0 || keyIdx >= AUTH_TREE_SIZE) throw new Error("tzel: WOTS+ key index out of range");
  const authPath = (p.authPath ?? []).map((s, i) => feltIn(s, `auth path sibling ${i}`));

  if (hex(depositPubkeyHash(authDomain, address.authRoot, address.pubSeed, blind)) !== hex(pubkeyHash)) throw new Error("tzel: the pool id does not belong to this address and blind");
  if (hex(deriveAuthPubSeed(askJ)) !== hex(address.pubSeed)) throw new Error("tzel: the signing seed does not match the address's public seed");
  const leaf = authLeaf(askJ, address.pubSeed, keyIdx);
  if (hex(authRootFromPath(address.pubSeed, leaf, keyIdx, authPath)) !== hex(address.authRoot)) throw new Error("tzel: the auth path does not lead to the address's root");

  const recipientNote = buildOutputNote(address, v, p.memo ?? "", { seed: outgoingSeed, role: "shield_output" });
  const producerNote = buildOutputNote(producer, producerFee, "dal", { seed: outgoingSeed, role: "producer_fee" });
  const sighash = shieldSighash({ authDomain, pubkeyHash, v, fee, producerFee, cmRecipient: recipientNote.cm, cmProducer: producerNote.cm, mhRecipient: recipientNote.mh, mhProducer: producerNote.mh });
  const signature = wotsSign(askJ, address.pubSeed, keyIdx, sighash);
  const witness = shieldWitness({ authDomain, pubkeyHash, v, fee, producerFee, recipientNote, producerNote, recipient: address, blind, keyIdx, signature, authPath, producer });
  return {
    witness,
    sighash: hex(sighash),
    clientCm: hex(recipientNote.cm), clientEnc: hex(encodeEncryptedNote(recipientNote.enc)), clientRseed: hex(recipientNote.rseed), clientMh: hex(recipientNote.mh),
    producerCm: hex(producerNote.cm), producerEnc: hex(encodeEncryptedNote(producerNote.enc)), producerMh: hex(producerNote.mh),
    publicOutputs: [authDomain, pubkeyHash, feltOfInt(v), feltOfInt(fee), feltOfInt(producerFee), recipientNote.cm, producerNote.cm, recipientNote.mh, producerNote.mh].map(hex),
  };
}

/**
 * The kernel inbox message for a proved shield, as hex for the operator. The proof bundle's
 * public outputs must be the nine the witness was built for (`publicOutputs` above), either
 * on their own or as the proving service returns them, behind the bootloader's header: the
 * task count (1), the task's output size (12), the program hash and the array length (9).
 * A prover that returns anything else is refused here rather than at the kernel.
 */
export async function tzelEncodeShieldMessage(json) {
  const m = typeof json === "string" ? JSON.parse(json) : json;
  const outputPreimage = m.outputPreimage.map((s, i) => feltIn(s, `public output ${i}`));
  if (m.expectedOutputs) {
    const expected = m.expectedOutputs.map((s, i) => feltIn(s, `expected output ${i}`));
    const same = (a, b) => a.length === b.length && a.every((f, i) => hex(f) === hex(b[i]));
    const header = [feltOfInt(1), feltOfInt(expected.length + 3), m.programHash ? feltIn(m.programHash, "program hash") : null, feltOfInt(expected.length)];
    const bootloader = outputPreimage.length === expected.length + 4
      && header.every((f, i) => f === null || hex(f) === hex(outputPreimage[i]))
      && same(expected, outputPreimage.slice(4));
    if (!same(expected, outputPreimage) && !bootloader) throw new Error(`tzel: the proof's public outputs (${outputPreimage.length}) are not the shield that was signed`);
  }
  return hex(encodeShieldMessage({
    pubkeyHash: feltIn(m.pubkeyHash, "pubkey_hash"), fee: mutez(m.fee, "fee"), v: mutez(m.v, "shield value"), producerFee: mutez(m.producerFee, "producer fee"),
    proofBytes: bytes(m.proofBytes, "proof bytes"), outputPreimage,
    clientCm: feltIn(m.clientCm, "client_cm"), clientEnc: decodeEncryptedNote(bytes(m.clientEnc, "client_enc")),
    producerCm: feltIn(m.producerCm, "producer_cm"), producerEnc: decodeEncryptedNote(bytes(m.producerEnc, "producer_enc")),
  }));
}
