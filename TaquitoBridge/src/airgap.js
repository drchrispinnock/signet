// AirGap Vault: the key is on a phone with no network, reached by QR codes. Swift shows the
// operation as a code, scans the Vault's signed reply and hands back the 64-byte ed25519
// signature, having checked that the Vault signed exactly the bytes it was given. Here the
// signature is checked once more against the account's key before Taquito may use it.

import { b58Encode, getPkhfromPk, hex2buf, PrefixV2, verifySignature } from "@tezos-x/octez.js-utils";

const g = globalThis;
const native = g.__signet;

const pendingSignatures = new Map();
let nextSignatureId = 1;

g.__signet_airgapDone = (id, signatureHex, errorMessage) => {
  const pending = pendingSignatures.get(id);
  if (!pending) return;
  pendingSignatures.delete(id);
  if (errorMessage) pending.reject(new Error(errorMessage));
  else pending.resolve(signatureHex);
};

/** The operation watermark: Vault signs blake2b(0x03 ‖ bytes) and nothing else. */
function isOperationWatermark(watermark) {
  return ArrayBuffer.isView(watermark) && watermark.length === 1 && watermark[0] === 3;
}

/**
 * A Taquito signer for `{ kind: "airgap", publicKey: "edpk…", address: "tz1…" }`. It signs
 * operations only: AirGap's transaction sign request carries forged operation bytes, so a
 * message, a multisig payload or a proof cannot be sent to the Vault this way.
 */
export function airGapSignerFor(s) {
  if (typeof s.address !== "string" || !s.address.startsWith("tz1")) throw new Error("signerFor: missing expected account address");
  if (typeof s.publicKey !== "string" || !s.publicKey.startsWith("edpk")) throw new Error("signerFor: an AirGap Vault account needs its edpk public key");
  let derived;
  try { derived = getPkhfromPk(s.publicKey); } catch (e) { throw new Error("signerFor: unreadable AirGap Vault public key"); }
  if (derived !== s.address) {
    throw new Error(`The stored public key derives ${derived} where ${s.address} was expected. The wallet directory may have changed.`);
  }
  return {
    publicKey: async () => s.publicKey,
    publicKeyHash: async () => s.address,
    secretKey: async () => undefined,
    async sign(message, watermark) {
      if (!isOperationWatermark(watermark)) throw new Error("AirGap Vault signs operations only; it cannot sign this message.");
      const bytes = typeof message === "string" ? message.toLowerCase() : Buffer.from(message).toString("hex");
      if (!/^([0-9a-f]{2})+$/.test(bytes)) throw new Error("AirGap Vault: the operation bytes are not hex");
      if (!native?.airgapSign) throw new Error("AirGap Vault signing is not available here.");
      const signatureHex = await new Promise((resolve, reject) => {
        const id = nextSignatureId++;
        pendingSignatures.set(id, { resolve, reject });
        native.airgapSign(id, JSON.stringify({ address: s.address, publicKey: s.publicKey, forged: bytes }));
      });
      if (typeof signatureHex !== "string" || !/^[0-9a-f]{128}$/.test(signatureHex)) throw new Error("AirGap Vault's reply carries no usable signature.");
      const signature = hex2buf(signatureHex);
      const prefixSig = b58Encode(signature, PrefixV2.Ed25519Signature);
      if (!verifySignature(bytes, s.publicKey, prefixSig, new Uint8Array([3]))) {
        throw new Error("AirGap Vault's signature is not valid for this account's key: the Vault may hold a different account. Nothing was sent.");
      }
      return { bytes, sig: b58Encode(signature, PrefixV2.GenericSignature), prefixSig, sbytes: bytes + signatureHex };
    },
  };
}
