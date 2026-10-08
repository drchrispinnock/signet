// Builds a Taquito signer from the JSON "signing key" Swift passes for an operation:
//   { "kind": "secret", "secretKey": "edsk…|edesk…", "passphrase": "…" }  — in-memory signing
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
    case "secret":
      return new InMemorySigner(s.secretKey, s.passphrase || undefined);
    default:
      throw new Error(`signerFor: unknown signing key kind ${s.kind}`);
  }
}

/** True for signers that need the user to act on a device. */
export function isLedgerSpec(spec) {
  const s = typeof spec === "string" ? JSON.parse(spec) : spec;
  return s?.kind === "ledger";
}
