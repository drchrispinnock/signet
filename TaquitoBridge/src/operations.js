// Executing an operation exactly as the user approved it (S14), and telling an unknown
// injection outcome apart from a rejection (S15).
//
// Native sends (transfer, staking, multisig) are estimated first; what the user approves is the
// estimate's fee, gas and storage, plus the reveal the node will need. Sending then prepares the
// operation again with those very limits, refuses it if anything about the cost differs, forges
// and signs it locally, preapplies it and injects it. The operation hash is computed before
// injection, so when the node's answer is lost the caller still learns the hash and that the
// outcome is unknown, instead of an error that invites a second payment.

import { blake2b } from "@noble/hashes/blake2.js";
import { RpcClient } from "@taquito/rpc";
import { forgeRawOperation } from "./rawforge.js";
import { localForger } from "@taquito/local-forging";
import { encodeOpHash, b58DecodeAndCheckPrefix, b58Encode, PrefixV2 } from "@taquito/utils";

/** Operations whose hash Taquito tracks for `waitForConfirmation` (sent in this session). */
export const pendingOperations = new Map();

const memoryJournal = new Map();
function records() {
  const saved = globalThis.__signet?.operationRead?.();
  const parsed = saved == null ? Array.from(memoryJournal.values()) : JSON.parse(saved);
  if (!Array.isArray(parsed)) throw new Error("Operation recovery storage is unavailable; refusing to sign");
  return parsed;
}
function save(record) {
  const error = globalThis.__signet?.operationSave?.(JSON.stringify(record));
  if (error) throw new Error(error);
  memoryJournal.set(record.hash, record);
}
export function forgetOperation(hash) {
  const error = globalThis.__signet?.operationRemove?.(hash);
  if (error) throw new Error(error);
  memoryJournal.delete(hash);
}
async function verifyRecoveryRecord(record) {
  if (!record.source) return; // Direct/offline injection fixtures have no account intent.
  if (!record.branch || !Array.isArray(record.contents) || !record.contents.length || record.contents.some(c => c.source !== record.source)) throw new Error("The recovery record's source does not match its signed intent");
  if (encodeOpHash(record.signedBytes) !== record.hash) throw new Error("The recovery record's hash does not match its signed bytes");
  let forged;
  try { forged = await localForger.forge({ branch: record.branch, contents: record.contents }); }
  catch { forged = forgeRawOperation(record.branch, record.contents); }
  if (!record.signedBytes.startsWith(forged) || record.signedBytes.length <= forged.length) throw new Error("The recovery record's displayed intent does not match its signed bytes");
}

export async function pendingOperation(rpcURL, source) {
  const chainID = await new RpcClient(rpcURL).getChainId();
  const record = records().find(r => r.source === source && (r.chainID == null || r.chainID === chainID));
  if (record) await verifyRecoveryRecord(record);
  return record ? { ...record, rpcURL } : null;
}
export async function assertNoPending(rpcURL, source) {
  const pending = await pendingOperation(rpcURL, source);
  if (pending) throw new Error(`Operation ${pending.hash} still needs recovery. Open Send to watch it or rebroadcast the same signed bytes; nothing new was signed.`);
  return new RpcClient(rpcURL).getChainId();
}
export function operationRecord(hash) { return records().find(r => r.hash === hash); }
export function recordCheckedLevel(hash, level) {
  const record = operationRecord(hash);
  if (record) save({ ...record, lastCheckedLevel: level });
}

/** First originated contract uses nonce zero, derived from the locally computed operation hash. */
export function originatedAddress(hash) {
  const bytes = b58DecodeAndCheckPrefix(hash, [PrefixV2.OperationHash], true);
  const nonce = new Uint8Array(bytes.length + 4);
  nonce.set(bytes);
  return b58Encode(blake2b(nonce, { dkLen: 20 }), PrefixV2.ContractHash);
}


export function checkedLimit(value, what = "limit") {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) throw new Error(`Invalid operation ${what}: ${JSON.stringify(value)}`);
  return number;
}

/** The approved limits as Swift serialises them; anything missing or malformed is refused. */
export function parseLimits(json) {
  const l = typeof json === "string" ? JSON.parse(json) : json;
  if (!l || typeof l !== "object") throw new Error("This operation was not estimated; estimate it before sending");
  const limits = { feeMutez: checkedLimit(l.feeMutez, "fee"), gasLimit: checkedLimit(l.gasLimit, "gas limit"), storageLimit: checkedLimit(l.storageLimit, "storage limit") };
  if (l.revealFeeMutez != null) {
    limits.revealFeeMutez = checkedLimit(l.revealFeeMutez, "reveal fee");
    limits.revealGasLimit = checkedLimit(l.revealGasLimit ?? 0, "reveal gas limit");
    limits.revealStorageLimit = checkedLimit(l.revealStorageLimit ?? 0, "reveal storage limit");
  }
  return limits;
}

/**
 * Checks prepared contents against the approved limits: exactly one operation, carrying the
 * approved fee, gas and storage, optionally preceded by a reveal within the approved reveal
 * budget. Pure, so it can be tested offline.
 */
export function checkApproved(contents, limits) {
  if (!Array.isArray(contents) || contents.length === 0) throw new Error("Nothing was prepared");
  const reveal = contents[0]?.kind === "reveal" ? contents[0] : null;
  const ops = reveal ? contents.slice(1) : contents;
  if (ops.length !== 1 || ops[0]?.kind === "reveal") throw new Error(`Expected one operation to send, found ${ops.length}`);
  const op = ops[0];
  if (checkedLimit(op.fee, "fee") !== limits.feeMutez || checkedLimit(op.gas_limit, "gas limit") !== limits.gasLimit || checkedLimit(op.storage_limit, "storage limit") !== limits.storageLimit) {
    throw new Error("The operation's fee, gas or storage are not what was approved; estimate it again");
  }
  if (reveal) {
    if (limits.revealFeeMutez == null) throw new Error("The account needs a reveal that was not part of the approved estimate; estimate it again");
    if (checkedLimit(reveal.fee, "reveal fee") > limits.revealFeeMutez || checkedLimit(reveal.gas_limit, "reveal gas") > limits.revealGasLimit || checkedLimit(reveal.storage_limit, "reveal storage") > limits.revealStorageLimit) {
      throw new Error("The reveal would cost more than approved; estimate it again");
    }
  }
  return { reveal, op };
}

/** Prepares `params` through `tk.prepare[method]` with the approved limits and checks the result. */
export async function prepareApproved(tk, method, params, limits) {
  if (typeof tk.prepare[method] !== "function") throw new Error(`Cannot prepare a ${method}`);
  const { opOb } = await tk.prepare[method]({ ...params, fee: limits.feeMutez, gasLimit: limits.gasLimit, storageLimit: limits.storageLimit });
  checkApproved(opOb.contents, limits);
  return opOb;
}

/**
 * The estimate's figures plus the limits to send with: the operation's own fee, gas and
 * storage, and the reveal Taquito will prepend for an unrevealed account, priced as it will
 * actually be sent. `feeMutez` is the whole fee the user pays.
 */
export async function approvedEstimate(tk, method, params, est) {
  const limits = { feeMutez: String(est.suggestedFeeMutez), gasLimit: est.gasLimit, storageLimit: est.storageLimit };
  const { opOb } = await tk.prepare[method]({ ...params, fee: Number(limits.feeMutez), gasLimit: est.gasLimit, storageLimit: est.storageLimit });
  const reveal = opOb.contents[0]?.kind === "reveal" ? opOb.contents[0] : null;
  if (reveal) {
    limits.revealFeeMutez = String(checkedLimit(reveal.fee, "reveal fee"));
    limits.revealGasLimit = checkedLimit(reveal.gas_limit, "reveal gas");
    limits.revealStorageLimit = checkedLimit(reveal.storage_limit, "reveal storage");
  }
  const fee = BigInt(limits.feeMutez) + BigInt(limits.revealFeeMutez ?? 0);
  const burn = BigInt(String(Math.round(Number(est.burnFeeMutez) || 0)));
  return { feeMutez: String(fee), burnMutez: String(burn), totalCostMutez: String(fee + burn), gasLimit: est.gasLimit, storageLimit: est.storageLimit, limits };
}

function describeFailure(results) {
  const failed = results.find((r) => r.metadata?.operation_result?.status !== "applied");
  const errors = failed?.metadata?.operation_result?.errors;
  return errors ? JSON.stringify(errors).slice(0, 400) : "no result";
}

/** Forges locally, signs, preapplies and injects `opOb` with the toolkit's signer. */
export async function signAndInject(tk, rpcUrl, opOb) {
  const { branch, contents, protocol } = opOb;
  const chainID = await assertNoPending(rpcUrl, await tk.signer.publicKeyHash());
  const forged = await localForger.forge({ branch, contents });
  const { prefixSig, sbytes } = await tk.signer.sign(forged, new Uint8Array([3]));
  const rpc = new RpcClient(rpcUrl);
  const replies = await rpc.preapplyOperations([{ branch, contents, protocol, signature: prefixSig }]);
  const results = replies.flatMap((r) => r.contents ?? []);
  if (results.length !== contents.length || results.some((c, i) => ["proposals", "ballot"].includes(contents[i].kind) ? c.kind !== contents[i].kind || c.metadata?.operation_result?.status === "failed" || !!c.errors : c.metadata?.operation_result?.status !== "applied")) {
    throw new Error(`The node did not apply the operation: ${describeFailure(results)}`);
  }
  return injectSigned(rpc, sbytes, { rpcURL: rpcUrl, source: contents[0].source, contents, chainID, branch });
}

/** Prepare with the approved limits, then sign and inject. */
export async function sendApproved(tk, rpcUrl, method, params, limits) {
  return signAndInject(tk, rpcUrl, await prepareApproved(tk, method, params, limits));
}

/**
 * Refuses a node that serves another chain than the one the user believes they are on (S12).
 * `expectedChainId` is null for networks that restart too often to pin one.
 */
export async function assertChain(rpcUrl, expectedChainId) {
  if (expectedChainId == null || expectedChainId === "") return { chainId: null };
  const chainId = await new RpcClient(rpcUrl).getChainId();
  if (chainId !== expectedChainId) throw new Error(`The node at ${new URL(rpcUrl).host} serves chain ${chainId}, not ${expectedChainId}. Check the node in Settings.`);
  return { chainId };
}

/**
 * Injects signed bytes. The operation hash is computed locally first, so when the node's answer
 * is lost after it may have taken the operation the caller still learns the hash and that the
 * outcome is unknown, instead of an error that invites a second, different payment (S15).
 * A definite rejection by the node is still thrown.
 */
export async function injectSigned(rpc, sbytes, intent = {}) {
  const hash = encodeOpHash(sbytes);
  const existing = records().find(r => r.hash === hash);
  // The head level now: where a watcher starts scanning. Looking the branch block up by hash
  // later is slow on some nodes (Etherlink's Michelson interface takes ~30 s), by level it is not.
  const headLevel = existing?.headLevel ?? await rpc.getBlockHeader().then((h) => h.level).catch(() => undefined);
  const record = { ...existing, ...intent, hash, injected: false, signedBytes: sbytes, headLevel, rpcURL: intent.rpcURL ?? existing?.rpcURL ?? rpc.getRpcUrl(), created: existing?.created ?? Date.now() };
  if (record.contents?.some(c => c.kind === "origination")) record.address = originatedAddress(hash);
  // Failure here occurs before the injection boundary and must prevent injection.
  save(record);
  try {
    const confirmed = await rpc.injectOperation(sbytes);
    if (confirmed !== hash) throw new Error("The node's operation hash does not match the signed bytes");
    // The durable record stays until inclusion is verified, including a crash after acceptance.
    return { ...record, injected: true };
  } catch (error) {
    // Even a Tezos error (e.g. counter_in_the_past) can follow an earlier successful acceptance.
    // Only pre-injection validation failures are safe to treat as definite failures.
    console.warn("injection outcome unknown", hash);
    return record;
  }
}

/** Sends already-signed bytes again after an unknown outcome; the hash cannot change (S15). */
export async function injectSignedBytes(rpcUrl, sbytes) {
  if (typeof sbytes !== "string" || !/^[0-9a-f]+$/i.test(sbytes) || sbytes.length < 2 * (32 + 64)) throw new Error("not a signed operation");
  const rpc = new RpcClient(rpcUrl);
  const chainID = await rpc.getChainId();
  const previous = operationRecord(encodeOpHash(sbytes));
  if (previous) await verifyRecoveryRecord(previous);
  if (previous?.chainID != null && previous.chainID !== chainID) throw new Error("This signed operation belongs to another chain; choose its original network");
  return injectSigned(rpc, sbytes, { rpcURL: rpcUrl, chainID });
}
