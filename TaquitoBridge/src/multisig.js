// Octez-client's generic multisig, driven through Taquito.
//
// A multisig is an originated contract (script in multisig-script.json, exactly as octez-client
// deploys it, so it recognises ours and we recognise its) whose storage is
// (Pair stored_counter (Pair threshold keys)). Spending is a call to its `main` entrypoint with
// (Pair (Pair counter action) sigs): `action` is `Left lambda`, the lambda does the transfer or
// changes the delegate, and
// `sigs` is one `Some signature` or `None` per key, in key order. Each signer signs
// pack (Pair (Pair chain_id contract_address) (Pair counter action)) with no watermark, which is
// what `octez-client sign multisig transaction` signs, so signatures from either tool combine.
// Lambdas are built exactly as octez's managed_contract.ml writes them (bytes literals, expanded
// macros), because the signed bytes must agree.

import { TezosToolkit } from "@taquito/taquito";
import { RpcClient } from "@taquito/rpc";
import { Parser, packDataBytes } from "@taquito/michel-codec";
import { b58Encode, PrefixV2, verifySignature } from "@taquito/utils";
import { blake2b } from "@noble/hashes/blake2.js";
import { signerFor } from "./signers.js";
import { encodedPublicKeyHash, encodedContractAddress } from "./rawforge.js";
import multisigScript from "./multisig-script.json";

/** Script_expr_hash of the generic multisig (`octez-client hash script`). */
export const GENERIC_MULTISIG_HASH = "exprub9UzpxmhedNQnsv1J1DazWGJnj1dLhtG1fxkUoWSdFLBGLqJ4";

const parser = new Parser();
const PAYLOAD_TYPE = parser.parseMichelineExpression(
  "(pair (pair chain_id address) (pair nat (or (lambda unit (list operation)) (pair nat (list key)))))"
);

function readOnlySigner(publicKey, address) {
  return {
    publicKey: async () => publicKey,
    publicKeyHash: async () => address,
    secretKey: async () => undefined,
    sign: async () => { throw new Error("read-only signer cannot sign"); },
  };
}

/** Script_expr_hash of a Micheline expression, as octez computes it: blake2b of its binary form. */
export function scriptExprHash(expr) {
  const packed = packDataBytes(expr).bytes;           // 05 + binary expression
  const bytes = Uint8Array.from(packed.slice(2).match(/../g).map((h) => parseInt(h, 16)));
  return b58Encode(blake2b(bytes, { dkLen: 32 }), PrefixV2.ScriptExpr);
}

/** Our embedded script's hash; must equal GENERIC_MULTISIG_HASH (checked by tests). */
export async function multisigScriptHash() {
  return { hash: scriptExprHash(multisigScript) };
}

function initialStorage(threshold, keys) {
  return { prim: "Pair", args: [{ int: "0" }, { prim: "Pair", args: [{ int: String(threshold) }, keys.map((k) => ({ string: k }))] }] };
}

function checkThreshold(threshold, keys) {
  if (!Array.isArray(keys) || keys.length === 0) throw new Error("A multisig needs at least one key");
  if (!(threshold >= 1)) throw new Error("The threshold must be at least 1");
  if (threshold > keys.length) throw new Error(`The threshold (${threshold}) cannot exceed the number of keys (${keys.length})`);
  if (new Set(keys).size !== keys.length) throw new Error("The same key is listed twice");
}

/** Fee and burn for deploying a multisig with `threshold` of `keys` from `source`. */
export async function multisigEstimateOriginate(rpcUrl, source, publicKey, threshold, keysJson) {
  const keys = JSON.parse(keysJson);
  checkThreshold(Number(threshold), keys);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  const est = await tk.estimate.originate({ code: multisigScript, init: initialStorage(threshold, keys) });
  return { feeMutez: String(est.suggestedFeeMutez), burnMutez: String(est.burnFeeMutez), totalCostMutez: String(est.totalCost), gasLimit: est.gasLimit, storageLimit: est.storageLimit };
}

/** Deploys a multisig. Returns the operation hash and the new contract's address. */
export async function multisigOriginate(rpcUrl, signerSpec, threshold, keysJson) {
  const keys = JSON.parse(keysJson);
  checkThreshold(Number(threshold), keys);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  const op = await tk.contract.originate({ code: multisigScript, init: initialStorage(threshold, keys) });
  await op.confirmation(1);
  return { hash: op.hash, address: op.contractAddress };
}

/** Counter, threshold, keys and balance of a multisig, and whether its code is the generic script. */
export async function multisigInfo(rpcUrl, address) {
  const rpc = new RpcClient(rpcUrl);
  const [script, balance] = await Promise.all([rpc.getScript(address), rpc.getBalance(address)]);
  const hash = scriptExprHash(script.code);
  const info = { address, balanceMutez: String(balance), scriptHash: hash, isGenericMultisig: hash === GENERIC_MULTISIG_HASH, counter: null, threshold: null, keys: [] };
  if (!info.isGenericMultisig) return info;
  const s = script.storage; // Pair counter (Pair threshold keys), possibly flattened by the node
  const flat = s.prim === "Pair" && s.args.length === 3 ? s.args : [s.args[0], s.args[1].args[0], s.args[1].args[1]];
  info.counter = flat[0].int;
  info.threshold = flat[1].int;
  info.keys = flat[2].map(keyFromMicheline);
  return info;
}

// Binary public key tag → base58 prefix, for keys the node hands back in optimized form.
const KEY_PREFIX_FOR_TAG = { "00": PrefixV2.Ed25519PublicKey, "01": PrefixV2.Secp256k1PublicKey, "02": PrefixV2.P256PublicKey, "03": PrefixV2.BLS12_381PublicKey, "04": PrefixV2.MLDSA44PublicKey };

/** A `key` literal from storage as base58, whether the node wrote it as a string or as bytes. */
function keyFromMicheline(node) {
  if (typeof node?.string === "string" && /^(edpk|sppk|p2pk|BLpk|mdpk)/.test(node.string)) return node.string;
  if (typeof node?.bytes === "string") {
    const prefix = KEY_PREFIX_FOR_TAG[node.bytes.slice(0, 2)];
    if (prefix) return b58Encode(Uint8Array.from(node.bytes.slice(2).match(/../g).map((h) => parseInt(h, 16))), prefix);
  }
  throw new Error(`The multisig lists a key in a form Signet cannot read: ${JSON.stringify(node)}`);
}

/** The public key an implicit account has revealed on chain, or null if it never has. */
export async function multisigRevealedKey(rpcUrl, address) {
  const key = await new RpcClient(rpcUrl).getManagerKey(address).catch(() => null);
  return { publicKey: typeof key === "string" ? key : key?.key ?? null };
}

/** Octez's lambda for "transfer amount to destination" (implicit account, or a contract's default unit entrypoint). */
export function transferLambda(destination, amountMutez) {
  const nilOp = { prim: "NIL", args: [{ prim: "operation" }] };
  const pushAmount = { prim: "PUSH", args: [{ prim: "mutez" }, { int: String(amountMutez) }] };
  const tail = [pushAmount, { prim: "UNIT" }, { prim: "TRANSFER_TOKENS" }, { prim: "CONS" }];
  if (destination.startsWith("KT1")) {
    return [
      { prim: "DROP" }, nilOp,
      { prim: "PUSH", args: [{ prim: "address" }, { bytes: encodedContractAddress(destination) }] },
      { prim: "CONTRACT", args: [{ prim: "unit" }] },
      [{ prim: "IF_NONE", args: [[[{ prim: "UNIT" }, { prim: "FAILWITH" }]], []] }],  // ASSERT_SOME expanded
      ...tail,
    ];
  }
  return [
    { prim: "DROP" }, nilOp,
    { prim: "PUSH", args: [{ prim: "key_hash" }, { bytes: encodedPublicKeyHash(destination) }] },
    { prim: "IMPLICIT_ACCOUNT" },
    ...tail,
  ];
}

/**
 * Octez's lambda for "set the delegate to `delegate`" (`null` withdraws it), as
 * client_proto_multisig.ml's Change_delegate writes it: a bytes literal for the key hash.
 */
export function delegateLambda(delegate) {
  const nilOp = { prim: "NIL", args: [{ prim: "operation" }] };
  const tail = [{ prim: "SET_DELEGATE" }, { prim: "CONS" }];
  if (delegate == null) {
    return [{ prim: "DROP" }, nilOp, { prim: "NONE", args: [{ prim: "key_hash" }] }, ...tail];
  }
  return [
    { prim: "DROP" }, nilOp,
    { prim: "PUSH", args: [{ prim: "key_hash" }, { bytes: encodedPublicKeyHash(delegate) }] },
    { prim: "SOME" },
    ...tail,
  ];
}

/**
 * The lambda for an action given as JSON: `{kind: "transfer", amountMutez, destination}` or
 * `{kind: "delegate", delegate: "tz1…" | null}`.
 */
export function lambdaFor(actionJson) {
  const action = typeof actionJson === "string" ? JSON.parse(actionJson) : actionJson;
  switch (action?.kind) {
    case "transfer":
      if (!action.destination || !/^\d+$/.test(String(action.amountMutez))) throw new Error("A transfer needs a destination and an amount in mutez");
      return transferLambda(action.destination, action.amountMutez);
    case "delegate":
      return delegateLambda(action.delegate ?? null);
    default:
      throw new Error(`Unknown multisig action ${JSON.stringify(action)}`);
  }
}

/** The bytes every signer signs for this action on this contract at this counter. */
export function multisigPayload(chainId, contract, counter, lambda) {
  const data = {
    prim: "Pair",
    args: [
      { prim: "Pair", args: [{ string: chainId }, { string: contract }] },
      { prim: "Pair", args: [{ int: String(counter) }, { prim: "Left", args: [lambda] }] },
    ],
  };
  return packDataBytes(data, PAYLOAD_TYPE).bytes;
}

/** Everything a signer needs: the multisig's state and the bytes to sign for this action. */
export async function multisigPrepare(rpcUrl, contract, actionJson) {
  const info = await multisigInfo(rpcUrl, contract);
  if (!info.isGenericMultisig) throw new Error(`${contract} is not a generic multisig contract (script ${info.scriptHash})`);
  const chainId = await new RpcClient(rpcUrl).getChainId();
  const lambda = lambdaFor(actionJson);
  const bytes = multisigPayload(chainId, contract, info.counter, lambda);
  return { ...info, chainId, bytes, lambda: JSON.stringify(lambda) };
}

/** Test hook: the bytes for an action without touching the network (compare with `octez-client prepare multisig transaction`). */
export async function multisigPayloadLocal(chainId, contract, counter, actionJson) {
  return { bytes: multisigPayload(chainId, contract, counter, lambdaFor(actionJson)) };
}

/** Test hook: packs the same payload through the node, to check our local packing against it. */
export async function multisigPayloadViaNode(rpcUrl, chainId, contract, counter, actionJson) {
  const rpc = new RpcClient(rpcUrl);
  const lambda = lambdaFor(actionJson);
  const data = {
    prim: "Pair",
    args: [
      { prim: "Pair", args: [{ string: chainId }, { string: contract }] },
      { prim: "Pair", args: [{ int: String(counter) }, { prim: "Left", args: [lambda] }] },
    ],
  };
  const r = await rpc.packData({ data, type: PAYLOAD_TYPE });
  return { bytes: r.packed, local: multisigPayload(chainId, contract, counter, lambda) };
}

/**
 * Places each signature against the key it verifies for, like octez-client: `Some sig` in that
 * key's slot, `None` elsewhere. A signature that matches no key, or fewer valid ones than the
 * threshold, is an error.
 */
export function arrangeSignatures(bytes, keys, threshold, signatures) {
  const slots = keys.map(() => null);
  const unmatched = [];
  for (const sig of signatures) {
    const i = keys.findIndex((k, idx) => slots[idx] === null && (() => { try { return verifySignature(bytes, k, sig); } catch { return false; } })());
    if (i < 0) unmatched.push(sig);
    else slots[i] = sig;
  }
  if (unmatched.length) throw new Error(`${unmatched.length === 1 ? "A signature does" : unmatched.length + " signatures do"} not match any key of this multisig for this transaction: ${unmatched.map((s) => s.slice(0, 12) + "…").join(", ")}`);
  const valid = slots.filter(Boolean).length;
  if (valid < Number(threshold)) throw new Error(`${valid} valid signature${valid === 1 ? "" : "s"} of the ${threshold} needed`);
  return slots;
}

function mainParameter(counter, lambda, slots) {
  return {
    prim: "Pair",
    args: [
      { prim: "Pair", args: [{ int: String(counter) }, { prim: "Left", args: [lambda] }] },
      slots.map((s) => (s ? { prim: "Some", args: [{ string: s }] } : { prim: "None" })),
    ],
  };
}

async function submitParams(rpcUrl, contract, actionJson, counter, signaturesJson) {
  const p = await multisigPrepare(rpcUrl, contract, actionJson);
  if (String(p.counter) !== String(counter)) {
    throw new Error(`This proposal was made for counter ${counter} but the multisig is now at ${p.counter}; the signatures no longer apply. Propose it again.`);
  }
  const slots = arrangeSignatures(p.bytes, p.keys, p.threshold, JSON.parse(signaturesJson));
  return { to: contract, amount: 0, mutez: true, parameter: { entrypoint: "main", value: mainParameter(p.counter, JSON.parse(p.lambda), slots) } };
}

/** Fee for submitting the action with the given signatures, paid by `source`. */
export async function multisigEstimateSubmit(rpcUrl, source, publicKey, contract, actionJson, counter, signaturesJson) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  const est = await tk.estimate.transfer(await submitParams(rpcUrl, contract, actionJson, counter, signaturesJson));
  return { feeMutez: String(est.suggestedFeeMutez), burnMutez: String(est.burnFeeMutez), totalCostMutez: String(est.totalCost), gasLimit: est.gasLimit, storageLimit: est.storageLimit };
}

/** Submits the action with the given signatures from the signer's account. Returns the operation hash. */
export async function multisigSubmit(rpcUrl, signerSpec, contract, actionJson, counter, signaturesJson) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  const op = await tk.contract.transfer(await submitParams(rpcUrl, contract, actionJson, counter, signaturesJson));
  await op.confirmation(1);
  return { hash: op.hash };
}
