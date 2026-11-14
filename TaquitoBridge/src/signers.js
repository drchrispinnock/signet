// Builds a Taquito signer from the JSON "signing key" Swift passes for an operation:
//   { "kind": "secret", "secretKey": "edsk…|edesk…", "passphrase": "…", "address": "tz1…" }  — in-memory signing
//   { "kind": "ledger", "path": "44'/1729'/0'/0'", "derivationType": 0, "address": "tz1…" }
//   { "kind": "enclave", "key": "<base64 blob>", "publicKey": "p2pk…", "address": "tz3…" }      — signed natively
// Secret keys only ever arrive here for the one operation and are not kept.

import { InMemorySigner } from "@taquito/signer";
import { b58Encode, getPkhfromPk, PrefixV2, verifySignature, hex2buf, buf2hex, mergebuf } from "@taquito/utils";
import { blake2b } from "@noble/hashes/blake2.js";
import { ledgerSignerFor } from "./ledger.js";

// ---- Secure Enclave: the digest goes to Swift, the Enclave signs it, r‖s comes back ---------
const pendingEnclave = new Map();
let nextEnclaveId = 1;

globalThis.__signet_enclaveDone = (id, signatureHex, errorMessage) => {
  const p = pendingEnclave.get(id);
  if (!p) return;
  pendingEnclave.delete(id);
  if (errorMessage) p.reject(new Error(errorMessage));
  else p.resolve(signatureHex);
};

function enclaveSign(key, digestHex, address) {
  const native = globalThis.__signet;
  if (!native || typeof native.enclaveSign !== "function") {
    return Promise.reject(new Error("Secure Enclave keys cannot sign here."));
  }
  return new Promise((resolve, reject) => {
    const id = nextEnclaveId++;
    pendingEnclave.set(id, { resolve, reject });
    native.enclaveSign(id, key, digestHex, address);
  });
}

/**
 * A signer for a tz3 key that lives in the Secure Enclave. The secret is never here: each
 * digest is signed natively after the user authenticates, and the signature is checked against
 * the account's public key before anything uses it, so a wrong or foreign key cannot sign.
 */
export function enclaveSignerFor(s) {
  if (typeof s.address !== "string" || !s.address.startsWith("tz3")) {
    throw new Error("signerFor: a Secure Enclave key is a tz3 account");
  }
  if (typeof s.key !== "string" || s.key.length === 0 || typeof s.publicKey !== "string" || !s.publicKey.startsWith("p2pk")) {
    throw new Error("signerFor: incomplete Secure Enclave key");
  }
  const found = getPkhfromPk(s.publicKey);
  if (found !== s.address) {
    throw new Error(`The stored key does not derive the account's address: it is ${found} where ${s.address} was expected. The wallet directory may have changed.`);
  }
  return {
    publicKey: async () => s.publicKey,
    publicKeyHash: async () => s.address,
    secretKey: async () => { throw new Error("A Secure Enclave key cannot be exported."); },
    sign: async (bytes, watermark) => {
      let message = hex2buf(bytes);
      if (watermark !== undefined) message = mergebuf(watermark, message);
      const digest = blake2b(message, { dkLen: 32 });
      const signatureHex = await enclaveSign(s.key, buf2hex(digest), s.address);
      if (typeof signatureHex !== "string" || !/^[0-9a-f]{128}$/.test(signatureHex)) {
        throw new Error("The Secure Enclave returned a malformed signature.");
      }
      const raw = hex2buf(signatureHex);
      const prefixSig = b58Encode(raw, PrefixV2.P256Signature);
      if (!verifySignature(bytes, s.publicKey, prefixSig, watermark)) {
        throw new Error("The Secure Enclave's signature does not verify for this account. Nothing was sent.");
      }
      return { bytes, sig: b58Encode(raw, PrefixV2.GenericSignature), prefixSig, sbytes: bytes + signatureHex };
    },
  };
}

export async function signerFor(spec) {
  const s = typeof spec === "string" ? JSON.parse(spec) : spec;
  if (!s || typeof s !== "object") throw new Error("signerFor: missing signing key");
  switch (s.kind) {
    case "ledger":
      return ledgerSignerFor(s);
    case "enclave":
      return enclaveSignerFor(s);
    case "secret": {
      if (typeof s.address !== "string" || s.address.trim().length === 0) {
        throw new Error("signerFor: missing expected account address");
      }
      const signer = new InMemorySigner(s.secretKey, s.passphrase || undefined);
      // The key was looked up by alias; make sure it is the account the user approved.
      const found = await signer.publicKeyHash();
      if (found !== s.address) {
        throw new Error(`The stored key does not derive the account's address: it is ${found} where ${s.address} was expected. The wallet directory may have changed.`);
      }
      return signer;
    }
    default:
      throw new Error(`signerFor: unknown signing key kind ${s.kind}`);
  }
}

/**
 * A signer that can identify the source but never sign: enough for estimation.
 *
 * Revealing a tz4 (BLS) account carries a proof of possession, a BLS signature over the public
 * key that only the secret key can make, and the node verifies it even when simulating, so
 * Taquito asks the signer for it while it prepares the reveal of an unrevealed tz4 account,
 * even to estimate. `publicKey` may therefore be `{ publicKey, proof }`, the proof made earlier
 * by `provePossession`; without one the estimate fails with "proof of possession required",
 * which Swift turns into `ChainError.proofOfPossessionRequired` and answers by making the proof.
 */
export function readOnlySigner(publicKey, address) {
  let proof;
  if (publicKey && typeof publicKey === "object") ({ publicKey, proof } = publicKey);
  const signer = {
    publicKey: async () => publicKey,
    publicKeyHash: async () => address,
    secretKey: async () => undefined,
    sign: async () => { throw new Error("read-only signer cannot sign"); },
  };
  if (typeof address === "string" && address.startsWith("tz4")) {
    signer.provePossession = async () => {
      if (typeof proof !== "string" || !proof.startsWith("BLsig")) {
        throw new Error("Revealing this tz4 account needs its key's proof of possession (proof of possession required)");
      }
      return { bytes: "", sig: proof, prefixSig: proof };
    };
  }
  return signer;
}

/** True for signers that need the user to act on a device. */
export function isLedgerSpec(spec) {
  const s = typeof spec === "string" ? JSON.parse(spec) : spec;
  return s?.kind === "ledger";
}
