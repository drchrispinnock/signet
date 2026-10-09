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

/** True for signers that need the user to act on a device. */
export function isLedgerSpec(spec) {
  const s = typeof spec === "string" ? JSON.parse(spec) : spec;
  return s?.kind === "ledger";
}
