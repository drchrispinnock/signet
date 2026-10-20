// Shielded tez (TzEL): what Swift calls for a shield. Everything crosses the bridge as hex
// strings or plain JSON; the protocol work is in tzel.js. Two kinds of export live here:
//
//   * the layer 1 deposit to the TzEL bridge ticketer (`mint`), an ordinary approved, locally
//     signed transaction like the Etherlink deposit in bridge.js;
//   * pure helpers over the wallet's secrets: key derivation for an address, deposit-pool ids,
//     the note scan, the shield and unshield witnesses and their kernel-wire encodings, and
//     the layer 1 execution of an unshield's outbox message once it can be. The auth tree itself is
//     built natively (XMSSAuthTree.swift); Swift hands the sibling path in and the witness
//     builder checks it against the address's root before signing.
//
// Every export is async so that a refusal rejects the promise and reaches Swift as the error
// text (the bridge turns a synchronous throw into "no result"). Secrets reach these functions
// the way a tz secret key reaches a signing call: per call, for the one job, never kept. Scanning gets the viewing material (`incoming_seed`, `nk`) only; the
// signing seeds (`ask_j`, or `ask_base` for an unshield's several addresses) and `outgoing_seed`
// come in for a shield or unshield alone.

import { TezosToolkit } from "@taquito/taquito";
import { signerFor, readOnlySigner } from "./signers.js";
import { approvedEstimate, sendApproved, parseLimits } from "./operations.js";
import {
  AUTH_TREE_SIZE, FELT_BYTES, MAX_UNSHIELD_INPUTS, TREE_DEPTH, acceptsNote, accountId, authLeaf, authRootFromPath, buildOutputNote, bytesToHex, commit, decodeEncryptedNote, decodePublishedNote, decryptMemo, depositBalanceKey, depositBlind, depositPubkeyHash, depositRecipient, deriveAccount, deriveAsk, deriveAuthPubSeed, deriveDiversifier, deriveNkSpend, deriveNkTag, deriveRcm, detect, encodeEncryptedNote, encodeShieldMessage, encodeUnshieldMessage, feltOfInt, hexToBytes, kemDetectSeed, kemKeygen, kemViewSeed, memoText, merklePath, merkleRoot, nullifier, ownerTag, paymentAddressFromJSON, shieldSighash, shieldWitness, unshieldSighash, unshieldWitness, wotsSign,
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
function verifiedOutputPreimage(m, what) {
  const outputPreimage = m.outputPreimage.map((s, i) => feltIn(s, `public output ${i}`));
  if (m.expectedOutputs) {
    const expected = m.expectedOutputs.map((s, i) => feltIn(s, `expected output ${i}`));
    const same = (a, b) => a.length === b.length && a.every((f, i) => hex(f) === hex(b[i]));
    const header = [feltOfInt(1), feltOfInt(expected.length + 3), m.programHash ? feltIn(m.programHash, "program hash") : null, feltOfInt(expected.length)];
    const bootloader = outputPreimage.length === expected.length + 4
      && header.every((f, i) => f === null || hex(f) === hex(outputPreimage[i]))
      && same(expected, outputPreimage.slice(4));
    if (!same(expected, outputPreimage) && !bootloader) throw new Error(`tzel: the proof's public outputs (${outputPreimage.length}) are not the ${what} that was signed`);
  }
  return outputPreimage;
}

export async function tzelEncodeShieldMessage(json) {
  const m = typeof json === "string" ? JSON.parse(json) : json;
  const outputPreimage = verifiedOutputPreimage(m, "shield");
  return hex(encodeShieldMessage({
    pubkeyHash: feltIn(m.pubkeyHash, "pubkey_hash"), fee: mutez(m.fee, "fee"), v: mutez(m.v, "shield value"), producerFee: mutez(m.producerFee, "producer fee"),
    proofBytes: bytes(m.proofBytes, "proof bytes"), outputPreimage,
    clientCm: feltIn(m.clientCm, "client_cm"), clientEnc: decodeEncryptedNote(bytes(m.clientEnc, "client_enc")),
    producerCm: feltIn(m.producerCm, "producer_cm"), producerEnc: decodeEncryptedNote(bytes(m.producerEnc, "producer_enc")),
  }));
}

// ---- Unshield -----------------------------------------------------------------------------------

/** The commitment of a note to the address with these fields (for checks and test doubles). */
export async function tzelNoteCommitment(dJHex, v, rseedHex, authRootHex, pubSeedHex, nkTagHex) {
  return hex(commit(feltIn(dJHex, "d_j"), mutez(v, "value"), deriveRcm(feltIn(rseedHex, "rseed")), ownerTag(feltIn(authRootHex, "auth_root"), feltIn(pubSeedHex, "pub_seed"), feltIn(nkTagHex, "nk_tag"))));
}

/** The root of the commitment tree holding `cms` (hex, in order) from position 0. */
export async function tzelMerkleRoot(cmsJson) {
  const cms = (typeof cmsJson === "string" ? JSON.parse(cmsJson) : cmsJson).map((h, i) => feltIn(h, `commitment ${i}`));
  return hex(merkleRoot(cms, TREE_DEPTH));
}

const RECIPIENT = /^(tz[1-4]|KT1)[1-9A-HJ-NP-Za-km-z]{33}$/;

/**
 * Builds an unshield of `vPub` mutez to the layer 1 account `recipient` from `inputs` (notes of
 * ours with the address each belongs to, the WOTS+ key index reserved for it and that key's
 * native auth path), paying `fee` to the rollup and `producerFee` to the DAL producer; what is
 * left over goes to `changeAddress` as a note of ours (it must be given when there is change).
 * `leafCms` is every commitment in the rollup's tree, in order, and must hash to `root`, the
 * root the proof is made against. Every input is checked before anything is signed: its
 * commitment is in the tree where the note says and recomputes from the note and its address,
 * the signing seed derives the address's public seed, and the auth path leads to its root.
 * The caller has already persisted every key index as used.
 */
export async function tzelBuildUnshield(json) {
  const p = typeof json === "string" ? JSON.parse(json) : json;
  const account = typeof p.account === "string" ? JSON.parse(p.account) : p.account;
  const nk = feltIn(account.nk, "nk"), askBase = feltIn(account.askBase, "ask_base"), outgoingSeed = feltIn(account.outgoingSeed, "outgoing_seed");
  const authDomain = feltIn(p.authDomain, "auth_domain"), root = feltIn(p.root, "root");
  const leafCms = (p.leafCms ?? []).map((h, i) => feltIn(h, `commitment ${i}`));
  if (leafCms.length === 0) throw new Error("tzel: the commitment tree is empty");
  if (hex(merkleRoot(leafCms, TREE_DEPTH)) !== hex(root)) throw new Error("tzel: the local copy of the commitment tree does not hash to the rollup's root; scan again");
  const vPub = mutez(p.vPub, "unshield value"), fee = mutez(p.fee, "fee"), producerFee = mutez(p.producerFee, "producer fee");
  if (vPub === 0n) throw new Error("tzel: an unshield of 0 tez is refused");
  if (producerFee === 0n) throw new Error("tzel: the producer fee must be positive");
  const recipient = String(p.recipient ?? "").trim();
  if (!RECIPIENT.test(recipient)) throw new Error(`tzel: the recipient must be a tz or KT1 address, not ${JSON.stringify(recipient)}`);
  const recipientId = accountId(recipient);
  const producer = paymentAddressFromJSON(p.producerAddress);
  if (!Array.isArray(p.inputs) || p.inputs.length === 0 || p.inputs.length > MAX_UNSHIELD_INPUTS) throw new Error("tzel: an unshield spends one to seven notes");

  const used = new Set();
  let sum = 0n;
  const inputs = p.inputs.map((i, at) => {
    const address = addressRecord(i.address);
    const index = i.note?.index;
    if (!Number.isInteger(index) || index < 0 || index >= leafCms.length) throw new Error(`tzel: input ${at} is not in the commitment tree`);
    const cm = feltIn(i.note.cm, `input ${at} commitment`), rseed = feltIn(i.note.rseed, `input ${at} rseed`), v = mutez(i.note.v, `input ${at} value`);
    if (hex(leafCms[index]) !== hex(cm)) throw new Error(`tzel: input ${at} is not the commitment at tree position ${index}`);
    if (hex(commit(address.dJ, v, deriveRcm(rseed), ownerTag(address.authRoot, address.pubSeed, address.nkTag))) !== hex(cm)) throw new Error(`tzel: input ${at} is not a note of address ${address.index}`);
    const askJ = deriveAsk(askBase, address.index);
    if (hex(deriveAuthPubSeed(askJ)) !== hex(address.pubSeed)) throw new Error(`tzel: the signing seed does not match address ${address.index}'s public seed`);
    const keyIdx = i.keyIdx;
    if (!Number.isInteger(keyIdx) || keyIdx < 0 || keyIdx >= AUTH_TREE_SIZE) throw new Error(`tzel: input ${at} has a WOTS+ key index out of range`);
    const key = `${address.index}/${keyIdx}`;
    if (used.has(key)) throw new Error(`tzel: WOTS+ key ${keyIdx} of address ${address.index} would sign twice`);
    used.add(key);
    const authPath = (i.authPath ?? []).map((s, k) => feltIn(s, `input ${at} auth path sibling ${k}`));
    if (hex(authRootFromPath(address.pubSeed, authLeaf(askJ, address.pubSeed, keyIdx), keyIdx, authPath)) !== hex(address.authRoot)) throw new Error(`tzel: input ${at}'s auth path does not lead to its address's root`);
    const nkSpend = deriveNkSpend(nk, address.dJ);
    sum += v;
    return { address, askJ, keyIdx, authPath, index, cm, rseed, v, nkSpend, nullifier: nullifier(nkSpend, cm, index), cmPath: merklePath(leafCms, TREE_DEPTH, index) };
  });
  const total = vPub + fee + producerFee;
  if (sum < total) throw new Error(`tzel: the inputs hold ${sum} mutez, less than the ${total} the unshield needs`);
  const changeValue = sum - total;
  let change = null;
  if (changeValue > 0n) {
    if (!p.changeAddress) throw new Error("tzel: the change needs an address");
    const address = { ...addressRecord(p.changeAddress), ekV: bytes(p.changeAddress.ekV, "ek_v", 1184), ekD: bytes(p.changeAddress.ekD, "ek_d", 1184) };
    change = { address, v: changeValue, note: buildOutputNote(address, changeValue, "", { seed: outgoingSeed, role: "unshield_change" }) };
  }
  const producerNote = buildOutputNote(producer, producerFee, "dal", { seed: outgoingSeed, role: "producer_fee" });
  const cmChange = change ? change.note.cm : feltOfInt(0), mhChange = change ? change.note.mh : feltOfInt(0);
  const nullifiers = inputs.map((i) => i.nullifier);
  const sighash = unshieldSighash({ authDomain, root, nullifiers, vPub, fee, recipientId, cmChange, mhChange, cmFee: producerNote.cm, mhFee: producerNote.mh });
  for (const i of inputs) i.signature = wotsSign(i.askJ, i.address.pubSeed, i.keyIdx, sighash);
  const witness = unshieldWitness({ inputs, authDomain, root, vPub, fee, recipientId, change, producer, producerFee, producerNote });
  return {
    witness,
    sighash: hex(sighash),
    recipientId: hex(recipientId),
    nullifiers: nullifiers.map(hex),
    changeMutez: changeValue.toString(10),
    changeCm: change ? hex(change.note.cm) : null, changeEnc: change ? hex(encodeEncryptedNote(change.note.enc)) : null,
    changeRseed: change ? hex(change.note.rseed) : null, changeMh: change ? hex(change.note.mh) : null,
    producerCm: hex(producerNote.cm), producerEnc: hex(encodeEncryptedNote(producerNote.enc)), producerMh: hex(producerNote.mh),
    publicOutputs: [authDomain, root, ...nullifiers, feltOfInt(vPub), feltOfInt(fee), recipientId, cmChange, mhChange, producerNote.cm, producerNote.mh].map(hex),
  };
}

/**
 * The kernel inbox message for a proved unshield, as hex for the operator; the proof's public
 * outputs must be the `2 + n + 7` the witness was built for, plain or behind the bootloader
 * header (see `tzelEncodeShieldMessage`).
 */
export async function tzelEncodeUnshieldMessage(json) {
  const m = typeof json === "string" ? JSON.parse(json) : json;
  const outputPreimage = verifiedOutputPreimage(m, "unshield");
  return hex(encodeUnshieldMessage({
    root: feltIn(m.root, "root"), nullifiers: m.nullifiers.map((s, i) => feltIn(s, `nullifier ${i}`)),
    vPub: mutez(m.vPub, "unshield value"), fee: mutez(m.fee, "fee"), recipient: String(m.recipient),
    cmChange: feltIn(m.cmChange, "cm_change"), changeEnc: m.changeEnc ? decodeEncryptedNote(bytes(m.changeEnc, "change note")) : null,
    proofBytes: bytes(m.proofBytes, "proof bytes"), outputPreimage,
    cmFee: feltIn(m.cmFee, "cm_fee"), producerEnc: decodeEncryptedNote(bytes(m.producerEnc, "producer note")),
  }));
}

// ---- Layer 1 outbox execution -------------------------------------------------------------------
//
// Once the rollup commitment covering an unshield is cemented (about 14 days on Shadownet),
// anyone can execute its outbox message: the ticketer's `burn`, which pays the recipient. The
// rollup node makes the proof; the operation is an ordinary approved, locally signed one.

function outboxParams(rollup, cementedCommitment, outputProofHex) {
  if (!/^sr1[1-9A-HJ-NP-Za-km-z]{33}$/.test(rollup)) throw new Error(`Not a Smart Rollup address: ${rollup}`);
  if (!/^src1[1-9A-HJ-NP-Za-km-z]{50}$/.test(cementedCommitment)) throw new Error(`Not a rollup commitment hash: ${cementedCommitment}`);
  const proof = bytes(outputProofHex, "outbox proof");
  if (proof.length === 0) throw new Error("tzel: the outbox proof is empty");
  return { rollup, cementedCommitment, outputProof: hex(proof) };
}

/** Fee, burn and limits for `source` executing the outbox message `outputProofHex` proves against `cementedCommitment`. */
export async function estimateOutboxExecution(rpcUrl, source, publicKey, rollup, cementedCommitment, outputProofHex) {
  const params = outboxParams(rollup, cementedCommitment, outputProofHex);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  return approvedEstimate(tk, "smartRollupExecuteOutboxMessage", params, await tk.estimate.smartRollupExecuteOutboxMessage(params));
}

/** Signs and injects the execution with exactly the approved limits (S14); `{ hash, injected, signedBytes }` (S15). */
export async function sendOutboxExecution(rpcUrl, signerSpec, rollup, cementedCommitment, outputProofHex, limitsJson) {
  const params = outboxParams(rollup, cementedCommitment, outputProofHex);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  return sendApproved(tk, rpcUrl, "smartRollupExecuteOutboxMessage", params, parseLimits(limitsJson));
}
