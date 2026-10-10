// Entry point for the Taquito bridge. Everything exported here becomes a property of the
// global `TaquitoBridge` object inside JavaScriptCore. Keep the surface small and async-friendly:
// Swift calls these functions and awaits the returned promises.
//
// Secret keys enter this runtime only for the single operation they sign (Taquito's
// InMemorySigner); Ledger keys never leave the device. Everything else is RPC, encoding and forging.

import "./polyfills.js";
import { TezosToolkit } from "@taquito/taquito";
import { validateAddress, ValidationResult } from "@taquito/utils";

const toolkits = new Map();

function toolkit(rpcUrl) {
  let tk = toolkits.get(rpcUrl);
  if (!tk) {
    tk = new TezosToolkit(rpcUrl);
    toolkits.set(rpcUrl, tk);
  }
  return tk;
}

export function version() {
  return "0.15.0";
}

/** Returns true if `address` is a well-formed implicit or contract address. */
export function isValidAddress(address) {
  return validateAddress(address) === ValidationResult.VALID;
}

/** Balance in mutez as a decimal string, so Swift can convert without float loss. */
export async function getBalanceMutez(rpcUrl, address) {
  const balance = await toolkit(rpcUrl).tz.getBalance(address);
  return balance.toString(10);
}

/** Head block hash and level, useful as a connectivity check. */
export async function getHead(rpcUrl) {
  const header = await toolkit(rpcUrl).rpc.getBlockHeader();
  return { hash: header.hash, level: header.level, chainId: header.chain_id };
}

// ---- Keys ------------------------------------------------------------------------------------
// tz1 and tz3 keys are generated in Swift with CryptoKit and never enter this runtime; Swift only
// asks for the address of a public key. tz2 and tz4 have no CryptoKit support, so they are
// generated here with the same @noble/curves code Taquito signs with.

import { InMemorySigner } from "@taquito/signer";
import { b58Encode, getPkhfromPk, PrefixV2, verifySignature as taquitoVerifySignature } from "@taquito/utils";
import { secp256k1 } from "@noble/curves/secp256k1";
import { bls12_381 } from "@noble/curves/bls12-381";
import { ml_dsa44 } from "@noble/post-quantum/ml-dsa.js";

/** tz address for a base58 public key (edpk, sppk, p2pk, BLpk). */
export function addressFromPublicKey(publicKey) {
  return getPkhfromPk(publicKey);
}

/** Generates a fresh tz2 or tz4 key pair. Returns base58 strings. */
export async function generateKeyPair(scheme) {
  let secretKey;
  switch (scheme) {
    case "tz2": {
      const sk = (secp256k1.utils.randomSecretKey ?? secp256k1.utils.randomPrivateKey)();
      secretKey = b58Encode(sk, PrefixV2.Secp256k1SecretKey);
      break;
    }
    case "tz4": {
      // noble produces a big-endian scalar; Tezos serialises BLS secret keys little-endian.
      const sk = (bls12_381.utils.randomSecretKey ?? bls12_381.utils.randomPrivateKey)();
      secretKey = b58Encode(new Uint8Array(sk).reverse(), PrefixV2.BLS12_381SecretKey);
      break;
    }
    case "tz5": {
      // ML-DSA-44 (post-quantum). Octez's mdsk payload is secretKey (2560 bytes) ‖ publicKey (1312 bytes),
      // which is what Taquito's MLDSAKey expects too.
      const seed = crypto.getRandomValues(new Uint8Array(32));
      const { secretKey: sk, publicKey: pk } = ml_dsa44.keygen(seed);
      const payload = new Uint8Array(sk.length + pk.length);
      payload.set(sk, 0);
      payload.set(pk, sk.length);
      secretKey = b58Encode(payload, PrefixV2.MLDSA44SecretKey);
      break;
    }
    default:
      throw new Error(`generateKeyPair: ${scheme} is generated natively in Swift, not in the bridge`);
  }
  const signer = new InMemorySigner(secretKey);
  return {
    secretKey,
    publicKey: await signer.publicKey(),
    address: await signer.publicKeyHash(),
  };
}

/** Public key and address for a base58 secret key. Used by tests to verify Swift-encoded keys. */
export async function keyInfoFromSecretKey(secretKey, passphrase) {
  const signer = new InMemorySigner(secretKey, passphrase || undefined);
  return { publicKey: await signer.publicKey(), address: await signer.publicKeyHash() };
}

// ---- Importing keys --------------------------------------------------------------------------------
import * as bip39 from "@scure/bip39";
import { wordlist as englishWordlist } from "@scure/bip39/wordlists/english.js";

/**
 * Checks a pasted secret key and describes it: clear or octez-encrypted (needs `passphrase`),
 * public key and address. A 64-byte ed25519 key (98-char edsk) is reduced to its 32-byte seed
 * (54-char edsk) so it can be stored and encrypted in octez's format.
 */
export async function inspectSecretKey(secretKey, passphrase) {
  const key = String(secretKey || "").trim();
  if (!key) throw new Error("Paste a secret key.");
  const encrypted = ["edesk", "spesk", "p2esk", "BLesk", "mdesk"].some((p) => key.startsWith(p));
  if (encrypted && !passphrase) return { encrypted: true, needsPassphrase: true };
  const signer = new InMemorySigner(key, passphrase || undefined);
  const [publicKey, address] = await Promise.all([signer.publicKey(), signer.publicKeyHash()]);
  return { encrypted, needsPassphrase: false, publicKey, address, secretKey: encrypted ? key : normalizeSecretKey(key) };
}

/** A 64-byte ed25519 secret (98-char edsk, seed ‖ public key) as its 32-byte seed (54-char edsk); anything else unchanged. */
function normalizeSecretKey(key) {
  if (key.startsWith("edsk") && key.length === 98) {
    const [raw] = b58DecodeAndCheckPrefix(key, [PrefixV2.Ed25519SecretKey]);
    return b58Encode(raw.slice(0, 32), PrefixV2.Ed25519Seed);
  }
  return key;
}

/** The clear base58 secret behind an octez-encrypted key (edesk…), opened with `passphrase`. */
export async function decryptSecretKey(secretKey, passphrase) {
  const signer = new InMemorySigner(String(secretKey || "").trim(), passphrase || undefined);
  return { secretKey: normalizeSecretKey(await signer.secretKey()) };
}

/** True when the words are a valid BIP39 English phrase (12, 15, 18, 21 or 24 words). */
export function validateMnemonic(mnemonic) {
  const words = String(mnemonic || "").trim().toLowerCase().split(/\s+/).filter(Boolean);
  const unknown = words.filter((w) => !englishWordlist.includes(w));
  return { valid: words.length > 0 && bip39.validateMnemonic(words.join(" "), englishWordlist), wordCount: words.length, unknownWords: unknown };
}

/**
 * Derives a key from a recovery phrase: BIP39 seed (with optional passphrase), then the Tezos
 * HD path (default 44'/1729'/0'/0') on the chosen curve (ed25519, secp256k1, p256, bip25519),
 * exactly as Taquito, Temple and Kukai do. Returns base58 secret key, public key and address.
 */
export async function keyFromMnemonic(mnemonic, passphrase, derivationPath, curve) {
  const words = String(mnemonic || "").trim().toLowerCase().split(/\s+/).filter(Boolean).join(" ");
  const signer = InMemorySigner.fromMnemonic({ mnemonic: words, password: passphrase || "", derivationPath: derivationPath || "44'/1729'/0'/0'", curve: curve || "ed25519" });
  const [secretKey, publicKey, address] = await Promise.all([signer.secretKey(), signer.publicKey(), signer.publicKeyHash()]);
  return { secretKey: normalizeSecretKey(secretKey), publicKey, address };
}

/** The legacy (fundraiser / non-HD) ed25519 derivation some old wallets used: mnemonic + email + password. */
export async function keyFromFundraiser(email, password, mnemonic) {
  const signer = InMemorySigner.fromFundraiser(email, password, String(mnemonic || "").trim().toLowerCase().split(/\s+/).join(" "));
  const [secretKey, publicKey, address] = await Promise.all([signer.secretKey(), signer.publicKey(), signer.publicKeyHash()]);
  return { secretKey: normalizeSecretKey(secretKey), publicKey, address };
}

// ---- Balances --------------------------------------------------------------------------------

/**
 * Full picture of an account's tez, all in mutez as decimal strings:
 * spendable + staked + unstakedFrozen + unstakedFinalizable = full.
 */
export async function getTezBalances(rpcUrl, address) {
  const rpc = toolkit(rpcUrl).rpc;
  // Accounts the chain has never seen return null for the staking fields, which Taquito turns
  // into a BigNumber error; treat anything unreadable as 0 so such accounts still show a balance.
  const zeroIfMissing = async (call) => {
    try {
      const value = await call();
      return value == null ? "0" : value.toString(10);
    } catch (e) {
      if (String(e?.message ?? e).includes("BigNumber Error")) return "0";
      throw e;
    }
  };
  // full_balance is the one field the node refuses (HTTP 500, "missing_key" storage error) for
  // an account the chain has never seen; report that as exists: false instead of throwing.
  const fullOrMissing = async () => {
    try {
      const value = await rpc.getFullBalance(address);
      return { full: value == null ? "0" : value.toString(10), exists: true };
    } catch (e) {
      const text = String(e?.message ?? e) + JSON.stringify(e?.body ?? e?.errors ?? "");
      if (text.includes("missing_key") || text.includes("storage_error")) return { full: null, exists: false };
      if (text.includes("BigNumber Error")) return { full: "0", exists: true };
      throw e;
    }
  };
  const [spendable, staked, unstakedFrozen, unstakedFinalizable, fullInfo] = await Promise.all([
    zeroIfMissing(() => rpc.getSpendable(address)),
    zeroIfMissing(() => rpc.getStakedBalance(address)),
    zeroIfMissing(() => rpc.getUnstakedFrozenBalance(address)),
    zeroIfMissing(() => rpc.getUnstakedFinalizableBalance(address)),
    fullOrMissing(),
  ]);
  return { spendable, staked, unstakedFrozen, unstakedFinalizable, full: fullInfo.full, exists: fullInfo.exists };
}

// ---- Transfers -------------------------------------------------------------------------------

/** A signer that can identify the source but never sign: enough for estimation. */
function readOnlySigner(publicKey, address) {
  return {
    publicKey: async () => publicKey,
    publicKeyHash: async () => address,
    secretKey: async () => undefined,
    sign: async () => { throw new Error("read-only signer cannot sign"); },
  };
}

/** Fee, burn and total for sending `amountMutez` from `source` to `destination`. No secret needed. */
export async function estimateTransfer(rpcUrl, source, publicKey, destination, amountMutez) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  const est = await tk.estimate.transfer({ to: destination, amount: Number(amountMutez), mutez: true });
  return {
    feeMutez: String(est.suggestedFeeMutez),
    burnMutez: String(est.burnFeeMutez),
    totalCostMutez: String(est.totalCost),
    gasLimit: est.gasLimit,
    storageLimit: est.storageLimit,
  };
}

const pendingOperations = new Map();

/** Signs (in memory or on a Ledger, see signers.js) and injects a transfer. Returns the operation hash. */
export async function sendTransfer(rpcUrl, signerSpec, destination, amountMutez) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  const op = await tk.contract.transfer({ to: destination, amount: Number(amountMutez), mutez: true });
  pendingOperations.set(op.hash, op);
  return { hash: op.hash };
}

/** Waits for `confirmations` blocks on an operation sent in this session. Returns the block level. */
export async function waitForConfirmation(hash, confirmations = 1) {
  const op = pendingOperations.get(hash);
  if (!op) throw new Error(`unknown operation ${hash}`);
  try {
    return await op.confirmation(confirmations);
  } finally {
    pendingOperations.delete(hash);
  }
}

// ---- Encrypted secret keys (octez-client format) ---------------------------------------------
// edesk / spesk / p2esk / BLesk = base58check(prefix ‖ salt[8] ‖ secretbox(key = PBKDF2-HMAC-SHA512(
// passphrase, salt, 32768 rounds, 32 bytes), nonce = 24 zero bytes, plaintext = raw secret)).
// Mirrors Taquito's decrypt path above and octez's src/lib_signer_backends/encrypted.ml.

import { b58DecodeAndCheckPrefix } from "@taquito/utils";
import { pbkdf2 } from "@noble/hashes/pbkdf2.js";
import { sha512 } from "@noble/hashes/sha2.js";
import { secretBox } from "@stablelib/nacl";

const ENCRYPTED_PREFIX_FOR = {
  [PrefixV2.Ed25519Seed]: PrefixV2.Ed25519EncryptedSeed,
  [PrefixV2.Secp256k1SecretKey]: PrefixV2.Secp256k1EncryptedSecretKey,
  [PrefixV2.P256SecretKey]: PrefixV2.P256EncryptedSecretKey,
  [PrefixV2.BLS12_381SecretKey]: PrefixV2.BLS12_381EncryptedSecretKey,
  [PrefixV2.MLDSA44SecretKey]: PrefixV2.MLDSA44EncryptedSecretKey,
};

/** Encrypts a clear-text base58 secret key (edsk seed, spsk, p2sk, BLsk) with `passphrase`. */
export function encryptSecretKey(secretKey, passphrase) {
  if (!passphrase) throw new Error("encryptSecretKey: passphrase is required");
  const [raw, prefix] = b58DecodeAndCheckPrefix(secretKey, Object.keys(ENCRYPTED_PREFIX_FOR));
  const salt = crypto.getRandomValues(new Uint8Array(8));
  const key = pbkdf2(sha512, passphrase, salt, { c: 32768, dkLen: 32 });
  const box = secretBox(key, new Uint8Array(24), raw);
  const payload = new Uint8Array(salt.length + box.length);
  payload.set(salt, 0);
  payload.set(box, salt.length);
  return b58Encode(payload, ENCRYPTED_PREFIX_FOR[prefix]);
}

// ---- Octez Connect (dApp connections) --------------------------------------------------------
export * from "./octezconnect.js";

// ---- Ledger ------------------------------------------------------------------------------------
import { signerFor } from "./signers.js";
export { ledgerDevices, ledgerAppVersion, ledgerGetAddress } from "./ledger.js";

/** Diagnostic: proves console output reaches the host. */
export function bridgeEcho(message) {
  console.log("echo:", message);
  console.warn("echo-warn:", message);
  return { echoed: message, consoleType: typeof console, logType: typeof console.log };
}

// ---- Delegation, staking and baking -----------------------------------------------------------

/** The account's delegate and, if it is a baker itself, its baker record. */
export async function getDelegateInfo(rpcUrl, address) {
  const base = rpcUrl.replace(/\/+$/, "");
  const get = async (path) => {
    const r = await fetch(`${base}${path}`);
    if (r.status === 404) return null;
    if (!r.ok) throw new Error(`RPC ${r.status} for ${path}`);
    return r.json();
  };
  const delegate = await get(`/chains/main/blocks/head/context/contracts/${address}/delegate`);
  // Nodes answer 404 or (on some networks) a 500 storage error for accounts that are not bakers.
  const record = await get(`/chains/main/blocks/head/context/delegates/${address}`).catch(() => null);
  let baker = null;
  if (record) {
    const keyOf = (v) => (v == null ? null : typeof v === "string" ? v : v.pkh ?? v.key ?? null);
    const pending = (v) => (Array.isArray(v) ? v.map((p) => ({ cycle: p.cycle, key: keyOf(p.pkh ?? p.key ?? p) })) : []);
    baker = {
      deactivated: !!record.deactivated,
      gracePeriod: record.grace_period ?? null,
      consensusKey: keyOf(record.active_consensus_key ?? record.consensus_key?.active),
      pendingConsensusKeys: pending(record.pending_consensus_keys ?? record.consensus_key?.pendings),
      companionKey: keyOf(record.active_companion_key ?? record.companion_key?.active),
      pendingCompanionKeys: pending(record.pending_companion_keys ?? record.companion_key?.pendings),
      ownFullBalanceMutez: record.own_full_balance ?? null,
      totalDelegatedStakeMutez: record.total_delegated_stake ?? null,
      stakingParameters: null,
      pendingStakingParameters: [],
    };
    const active = await get(`/chains/main/blocks/head/context/delegates/${address}/active_staking_parameters`).catch(() => null);
    if (active) baker.stakingParameters = { limitMillionth: Number(active.limit_of_staking_over_baking_millionth ?? 0), edgeBillionth: Number(active.edge_of_baking_over_staking_billionth ?? 0) };
    const pendingParams = await get(`/chains/main/blocks/head/context/delegates/${address}/pending_staking_parameters`).catch(() => null);
    if (Array.isArray(pendingParams)) {
      baker.pendingStakingParameters = pendingParams.map((p) => ({
        cycle: p.cycle ?? null,
        limitMillionth: Number(p.parameters?.limit_of_staking_over_baking_millionth ?? p.limit_of_staking_over_baking_millionth ?? 0),
        edgeBillionth: Number(p.parameters?.edge_of_baking_over_staking_billionth ?? p.edge_of_baking_over_staking_billionth ?? 0),
      }));
    }
  }
  let acceptsStaking = null;
  if (delegate) {
    const params = await get(`/chains/main/blocks/head/context/delegates/${delegate}/active_staking_parameters`).catch(() => null);
    if (params) acceptsStaking = Number(params.limit_of_staking_over_baking_millionth ?? 0) > 0;
  }
  return { delegate: delegate ?? null, isBaker: baker != null, baker, acceptsStaking };
}

function stakingCall(tk, kind, arg) {
  switch (kind) {
    case "setDelegate": return (p) => p.setDelegate({ delegate: arg.delegate || undefined, source: arg.source });
    case "registerDelegate": return (p) => p.registerDelegate({});
    case "stake": return (p) => p.stake({ amount: Number(arg.amountMutez), mutez: true });
    case "unstake": return (p) => p.unstake({ amount: Number(arg.amountMutez), mutez: true });
    case "finalizeUnstake": return (p) => p.finalizeUnstake({});
    case "updateConsensusKey": return (p) => p.updateConsensusKey({ pk: arg.pk, ...(arg.proof ? { proof: arg.proof } : {}) });
    case "updateCompanionKey": return (p) => p.updateCompanionKey({ pk: arg.pk, ...(arg.proof ? { proof: arg.proof } : {}) });
    case "setDelegateParameters":
      // A transaction to self with the set_delegate_parameters entrypoint: Pair limit (Pair edge Unit).
      return (p) => p.transfer({
        to: arg.source, amount: 0, mutez: true,
        parameter: {
          entrypoint: "set_delegate_parameters",
          value: { prim: "Pair", args: [{ int: String(arg.limitMillionth) }, { prim: "Pair", args: [{ int: String(arg.edgeBillionth) }, { prim: "Unit" }] }] },
        },
      });
    default: throw new Error(`unknown staking operation ${kind}`);
  }
}

/** Fee/total for a staking-family operation, with a read-only signer (no secret needed). */
export async function estimateStakingOperation(rpcUrl, source, publicKey, kind, argJson) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  const arg = JSON.parse(argJson || "{}");
  const est = await stakingCall(tk, kind, { ...arg, source })(tk.estimate);
  return { feeMutez: String(est.suggestedFeeMutez), burnMutez: String(est.burnFeeMutez), totalCostMutez: String(est.totalCost), gasLimit: est.gasLimit, storageLimit: est.storageLimit };
}

/** Signs and injects a staking-family operation. Returns the operation hash. */
export async function sendStakingOperation(rpcUrl, signerSpec, kind, argJson) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  const arg = JSON.parse(argJson || "{}");
  const op = await stakingCall(tk, kind, arg)(tk.contract);
  pendingOperations.set(op.hash, op);
  return { hash: op.hash };
}

/** BLS proof of possession for a tz4 key, required when it becomes a consensus or companion key. */
export async function provePossession(signerSpec) {
  const signer = await signerFor(signerSpec);
  if (typeof signer.provePossession !== "function") throw new Error("this key type cannot produce a proof of possession");
  const proof = await signer.provePossession();
  return { proof: typeof proof === "string" ? proof : proof?.prefixSig ?? proof?.sig ?? String(proof) };
}

// ---- Message signing ----------------------------------------------------------------------------

/** Signs arbitrary bytes (hex, typically a 0x05-packed Micheline string) with no watermark. */
export async function signPayload(signerSpec, payloadHex) {
  const signer = await signerFor(signerSpec);
  const [publicKey, address] = await Promise.all([signer.publicKey(), signer.publicKeyHash()]);
  const { prefixSig, sig } = await signer.sign(payloadHex);
  return { publicKey, address, signature: prefixSig, genericSignature: sig };
}

/** True when `signature` (prefixed) is a valid signature of `payloadHex` by `publicKey`. */
export function verifySignature(payloadHex, publicKey, signature) {
  return taquitoVerifySignature(payloadHex, publicKey, signature);
}

// ---- Governance (on-chain voting) -------------------------------------------------------------

/** The current voting period and what `address` can do in it. */
export async function getGovernanceInfo(rpcUrl, address) {
  const base = rpcUrl.replace(/\/+$/, "");
  const get = async (path, fallback = null) => {
    const r = await fetch(`${base}/chains/main/blocks/head/votes/${path}`);
    if (!r.ok) return fallback;
    return r.json();
  };
  const [period, proposals, currentProposal, listings, ballots, ballotList, totalPower, quorum, proposalCount] = await Promise.all([
    get("current_period"), get("proposals", []), get("current_proposal"), get("listings", []),
    get("ballots", { yay: "0", nay: "0", pass: "0" }), get("ballot_list", []), get("total_voting_power", "0"),
    get("current_quorum", null), get(`proposal_count/${address}`, 0),
  ]);
  const mine = Array.isArray(listings) ? listings.find((l) => l.pkh === address) : null;
  const myBallot = Array.isArray(ballotList) ? ballotList.find((b) => b.pkh === address)?.ballot ?? null : null;
  return {
    kind: period?.voting_period?.kind ?? null,
    index: period?.voting_period?.index ?? null,
    position: period?.position ?? null,
    remaining: period?.remaining ?? null,
    proposals: (Array.isArray(proposals) ? proposals : []).map(([hash, power]) => ({ hash, votingPower: String(power) })),
    currentProposal: currentProposal ?? null,
    votingPower: mine ? String(mine.voting_power) : null,
    totalVotingPower: String(totalPower ?? "0"),
    quorumPerTenThousand: quorum ?? null,
    ballots: { yay: String(ballots?.yay ?? "0"), nay: String(ballots?.nay ?? "0"), pass: String(ballots?.pass ?? "0") },
    myBallot,
    proposalCount: Number(proposalCount ?? 0),
  };
}

/** Injects a `proposals` (upvote) or `ballot` operation. Voting operations carry no fee. */
export async function sendGovernanceOperation(rpcUrl, signerSpec, kind, argJson) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  const arg = JSON.parse(argJson || "{}");
  let op;
  switch (kind) {
    case "proposals": op = await tk.contract.proposals({ proposals: arg.proposals }); break;
    case "ballot": op = await tk.contract.ballot({ proposal: arg.proposal, ballot: arg.ballot }); break;
    default: throw new Error(`unknown governance operation ${kind}`);
  }
  pendingOperations.set(op.hash, op);
  return { hash: op.hash };
}

// ---- Raw operations ---------------------------------------------------------------------------
// For contents Taquito cannot build or forge itself (e.g. update_consensus_key with a tz6/XMSS key):
// the node simulates and preapplies, but the bytes we sign are forged here (`rawforge.js`) and
// the node's forging must match them, so a lying node cannot swap in another operation.

import { RpcClient } from "@taquito/rpc";
import { forgeRawOperation, verifyRawForging } from "./rawforge.js";

const MINIMAL_FEE = 100, FEE_PER_BYTE = 1, NANOTEZ_PER_GAS = 100, SIGNATURE_BYTES = 64;
const HARD_GAS_LIMIT = 1040000, HARD_STORAGE_LIMIT = 60000;

/** Every content's simulation result, all applied, or an error. */
function appliedResults(contents, replies, stage) {
  const results = replies.map((c) => c.metadata?.operation_result);
  if (results.length !== contents.length || results.some((r) => !r)) {
    throw new Error(`${stage} returned ${results.length} results for ${contents.length} operations`);
  }
  const failed = results.find((r) => r.status !== "applied");
  if (failed) throw new Error(`${stage} failed: ${JSON.stringify(failed.errors ?? failed)}`);
  return results;
}

async function prepareRaw(rpcUrl, source, publicKey, contentsIn) {
  const rpc = new RpcClient(rpcUrl);
  const [branch, chainId, contract, protocols, managerKey] = await Promise.all([
    rpc.getBlockHash(), rpc.getChainId(), rpc.getContract(source), rpc.getProtocols(), rpc.getManagerKey(source).catch(() => null),
  ]);
  let counter = Number(contract.counter) + 1;
  const contents = [];
  if (!managerKey) contents.push({ kind: "reveal", source, public_key: publicKey, fee: "0", counter: String(counter++), gas_limit: "10000", storage_limit: "0" });
  for (const c of contentsIn) contents.push({ ...c, source, fee: "0", counter: String(counter++), gas_limit: String(HARD_GAS_LIMIT), storage_limit: String(HARD_STORAGE_LIMIT) });

  const sim = await rpc.simulateOperation({ operation: { branch, contents }, chain_id: chainId });
  const results = appliedResults(contents, sim.contents, "simulation");
  let totalGas = 0;
  const sized = contents.map((c, i) => {
    const r = results[i];
    // The node's numbers only size the limits and fee, which the user sees before signing; cap them anyway.
    const gas = Math.min(Math.ceil(Number(r.consumed_milligas ?? 0) / 1000) + 100, HARD_GAS_LIMIT);
    const storage = Math.min(Number(r.paid_storage_size_diff ?? 0) + (r.allocated_destination_contract ? 257 : 0), HARD_STORAGE_LIMIT);
    totalGas += gas;
    return { ...c, gas_limit: String(gas), storage_limit: String(storage) };
  });
  const bytes = forgeRawOperation(branch, sized).length / 2 + SIGNATURE_BYTES;
  const fee = MINIMAL_FEE + FEE_PER_BYTE * (bytes + 8) + Math.ceil((NANOTEZ_PER_GAS * totalGas) / 1000) + 50;
  sized[sized.length - 1].fee = String(fee);
  const forged = verifyRawForging(branch, sized, await rpc.forgeOperations({ branch, contents: sized }));
  return { rpc, branch, contents: sized, forged, feeMutez: fee, protocol: protocols.protocol };
}

/** Fee for a raw operation, computed from the node's simulation. */
export async function estimateRawOperation(rpcUrl, source, publicKey, contentsJson) {
  const { feeMutez, contents } = await prepareRaw(rpcUrl, source, publicKey, JSON.parse(contentsJson));
  return { feeMutez: String(feeMutez), burnMutez: "0", totalCostMutez: String(feeMutez), gasLimit: contents.reduce((a, c) => a + Number(c.gas_limit), 0), storageLimit: 0 };
}

/** Signs and injects raw contents from the signer's account. Returns the operation hash. */
export async function sendRawOperation(rpcUrl, signerSpec, contentsJson) {
  const signer = await signerFor(signerSpec);
  const [source, publicKey] = await Promise.all([signer.publicKeyHash(), signer.publicKey()]);
  const { rpc, branch, contents, forged, protocol } = await prepareRaw(rpcUrl, source, publicKey, JSON.parse(contentsJson));
  const { prefixSig, sbytes } = await signer.sign(forged, new Uint8Array([3]));
  const pre = await rpc.preapplyOperations([{ branch, contents, protocol, signature: prefixSig }]);
  appliedResults(contents, pre.flatMap((p) => p.contents), "preapply");
  const hash = await rpc.injectOperation(sbytes);
  return { hash };
}

// Test hooks for the local forger: our bytes, Taquito's for the same contents, and the check.
import { localForger } from "@taquito/local-forging";
export async function forgeRawForTest(branch, contentsJson) { return forgeRawOperation(branch, JSON.parse(contentsJson)); }
export async function taquitoForgeForTest(branch, contentsJson) { return localForger.forge({ branch, contents: JSON.parse(contentsJson) }); }
export async function verifyRawForgingForTest(branch, contentsJson, nodeHex) { return verifyRawForging(branch, JSON.parse(contentsJson), nodeHex); }

/** Waits for a raw operation to appear in a block (manager operations live in validation pass 3). */
export async function waitForRawOperation(rpcUrl, hash, maxBlocks = 12) {
  const rpc = new RpcClient(rpcUrl);
  let last = (await rpc.getBlockHeader()).level;
  for (let seen = 0; seen < maxBlocks; ) {
    const header = await rpc.getBlockHeader();
    if (header.level > last) {
      for (let level = last + 1; level <= header.level; level++) {
        const block = await rpc.getBlock({ block: String(level) });
        if ((block.operations?.[3] ?? []).some((op) => op.hash === hash)) return level;
      }
      seen += header.level - last;
      last = header.level;
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error(`operation ${hash} not seen in ${maxBlocks} blocks`);
}
