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
  return "0.3.0";
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
export async function keyInfoFromSecretKey(secretKey) {
  const signer = new InMemorySigner(secretKey);
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
  const [spendable, staked, unstakedFrozen, unstakedFinalizable, full] = await Promise.all([
    zeroIfMissing(() => rpc.getSpendable(address)),
    zeroIfMissing(() => rpc.getStakedBalance(address)),
    zeroIfMissing(() => rpc.getUnstakedFrozenBalance(address)),
    zeroIfMissing(() => rpc.getUnstakedFinalizableBalance(address)),
    zeroIfMissing(() => rpc.getFullBalance(address)),
  ]);
  return { spendable, staked, unstakedFrozen, unstakedFinalizable, full };
}
