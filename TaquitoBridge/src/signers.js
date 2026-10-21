// Builds a Taquito signer from the JSON "signing key" Swift passes for an operation:
//   { "kind": "secret", "secretKey": "edsk…|edesk…", "passphrase": "…", "address": "tz1…" }  — in-memory signing
//   { "kind": "ledger", "path": "44'/1729'/0'/0'", "derivationType": 0, "address": "tz1…" }
// Secret keys only ever arrive here for the one operation and are not kept.

import { InMemorySigner } from "@taquito/signer";
import { ledgerSignerFor } from "./ledger.js";

export async function signerFor(spec) {
  const s = typeof spec === "string" ? JSON.parse(spec) : spec;
  if (!s || typeof s !== "object") throw new Error("signerFor: missing signing key");
  switch (s.kind) {
    case "ledger":
      return ledgerSignerFor(s);
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
