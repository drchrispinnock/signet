// Entry point for the Taquito bridge. Everything exported here becomes a property of the
// global `TaquitoBridge` object inside JavaScriptCore. Keep the surface small and async-friendly:
// Swift calls these functions and awaits the returned promises.
//
// Private keys never enter this runtime. Signing is done in Swift; this bundle only does RPC,
// encoding and forging work.

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
  return "0.8.0";
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
import { b58Encode, getPkhfromPk, PrefixV2 } from "@taquito/utils";
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

/** Signs and injects a transfer with `secretKey` (base58, unencrypted). Returns the operation hash. */
export async function sendTransfer(rpcUrl, secretKey, passphrase, destination, amountMutez) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(new InMemorySigner(secretKey, passphrase || undefined));
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

/** Diagnostic: proves console output reaches the host. */
export function bridgeEcho(message) {
  console.log("echo:", message);
  console.warn("echo-warn:", message);
  return { echoed: message, consoleType: typeof console, logType: typeof console.log };
}
