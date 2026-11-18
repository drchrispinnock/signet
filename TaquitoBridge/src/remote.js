// Remote signers (octez-signer over HTTP, HTTPS, TCP or a Unix socket). Swift does the talking
// (`RemoteSignerClient.swift`) and hands back the signature as the signer gave it: base58 over
// HTTP, raw bytes over a socket. Here it is put in the key's own form and checked against the
// account's public key, so a signer that answers with another key's signature, or a network
// in between that alters it, cannot get anything signed in the account's name.

import { b58DecodeAndCheckPrefix, b58Encode, getPkhfromPk, hex2buf, PrefixV2, signaturePrefixes, verifySignature } from "@tezos-x/octez.js-utils";

const g = globalThis;
const native = g.__signet;

const pending = new Map();
let nextId = 1;

g.__signet_remoteDone = (id, replyJSON, errorMessage) => {
  const p = pending.get(id);
  if (!p) return;
  pending.delete(id);
  if (errorMessage) p.reject(new Error(errorMessage));
  else p.resolve(replyJSON);
};

function askNative(request) {
  if (!native?.remoteSign) return Promise.reject(new Error("Remote signers are not available here."));
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    native.remoteSign(id, JSON.stringify(request));
  });
}

/** The signature prefix, the raw length and the operation marker (Octez signature_v3) for a public key. */
const KEY_FORMS = {
  edpk: { prefix: PrefixV2.Ed25519Signature, lengths: [64], marker: "" },
  sppk: { prefix: PrefixV2.Secp256k1Signature, lengths: [64], marker: "" },
  p2pk: { prefix: PrefixV2.P256Signature, lengths: [64], marker: "" },
  BLpk: { prefix: PrefixV2.BLS12_381Signature, lengths: [96], marker: "ff03" },
  mdpk: { prefix: PrefixV2.MLDSA44Signature, lengths: [2420], marker: "ff04" },
};

function formFor(publicKey) {
  const form = KEY_FORMS[publicKey.slice(0, 4)];
  if (!form) throw new Error("signerFor: unsupported public key for a remote signer");
  return form;
}

/** The raw signature bytes in Swift's reply: `{signature: base58}` or `{raw: hex}`. */
export function rawSignature(replyJSON, publicKey) {
  const reply = typeof replyJSON === "string" ? JSON.parse(replyJSON) : replyJSON;
  const form = formFor(publicKey);
  let raw;
  if (typeof reply?.raw === "string" && /^([0-9a-f]{2})+$/.test(reply.raw)) {
    raw = hex2buf(reply.raw);
  } else if (typeof reply?.signature === "string") {
    try { [raw] = b58DecodeAndCheckPrefix(reply.signature, signaturePrefixes); }
    catch (e) { throw new Error("The remote signer's signature could not be read."); }
  } else {
    throw new Error("The remote signer's reply carries no signature.");
  }
  // A variable-length signature may come with its own marker; keep the bare signature.
  if (form.marker && raw.length === form.lengths[0] + 2 && raw[0] === 0xff) raw = raw.slice(2);
  if (!form.lengths.includes(raw.length)) throw new Error("The remote signer's signature has the wrong length for this key.");
  return raw;
}

/**
 * A Taquito signer for `{ kind: "remote", locator, publicKey, address }`. It signs whatever
 * Taquito asks (operations with 0x03, raw payloads with none); the signer's own policy decides
 * what it accepts.
 */
export function remoteSignerFor(s) {
  if (typeof s.address !== "string" || s.address.trim().length === 0) throw new Error("signerFor: missing expected account address");
  if (typeof s.locator !== "string" || s.locator.length === 0) throw new Error("signerFor: missing remote signer locator");
  if (typeof s.publicKey !== "string") throw new Error("signerFor: a remote signer account needs its public key");
  formFor(s.publicKey);
  let derived;
  try { derived = getPkhfromPk(s.publicKey); } catch (e) { throw new Error("signerFor: unreadable public key"); }
  if (derived !== s.address) throw new Error(`The stored public key derives ${derived} where ${s.address} was expected. The wallet directory may have changed.`);
  const form = formFor(s.publicKey);
  return {
    publicKey: async () => s.publicKey,
    publicKeyHash: async () => s.address,
    secretKey: async () => undefined,
    async sign(message, watermark) {
      const bytes = typeof message === "string" ? message.toLowerCase() : Buffer.from(message).toString("hex");
      if (!/^([0-9a-f]{2})*$/.test(bytes)) throw new Error("Remote signer: the bytes to sign are not hex");
      const mark = watermark ? Buffer.from(watermark).toString("hex") : "";
      const reply = await askNative({ op: "sign", locator: s.locator, address: s.address, bytes: mark + bytes });
      const raw = rawSignature(reply, s.publicKey);
      const prefixSig = b58Encode(raw, form.prefix);
      if (!verifySignature(bytes, s.publicKey, prefixSig, watermark || undefined)) {
        const hint = s.publicKey.startsWith("BLpk") ? " A tz4 key needs octez-signer 23 or later, which makes the BLS signatures the chain accepts." : " The signer may hold a different key under this address.";
        throw new Error(`The remote signer's signature is not valid for this account's key.${hint} Nothing was sent.`);
      }
      const rawHex = Buffer.from(raw).toString("hex");
      return { bytes, sig: s.publicKey.startsWith("md") ? prefixSig : b58Encode(raw, PrefixV2.GenericSignature), prefixSig, sbytes: bytes + form.marker + rawHex };
    },
    async provePossession() {
      if (!s.publicKey.startsWith("BLpk")) throw new Error("Only BLS keys can prove possession");
      const reply = JSON.parse(await askNative({ op: "prove", locator: s.locator, address: s.address }));
      const proof = reply?.proof;
      if (typeof proof !== "string" || !proof.startsWith("BLsig")) throw new Error("The remote signer did not give a proof of possession.");
      if (!verifySignature(b58DecodeAndCheckPrefix(s.publicKey, [PrefixV2.BLS12_381PublicKey])[0], s.publicKey, proof, undefined, true)) {
        throw new Error("The remote signer's proof of possession is not valid for this key.");
      }
      return { bytes: "", sig: proof, prefixSig: proof };
    },
  };
}
