// Local forging for the raw operation path (S01).
//
// Operations Taquito cannot encode (a tz6/XMSS consensus key) used to be forged by the node and
// signed as returned, so a malicious node could hand back a transfer and get it signed. The three
// kinds this path carries are encoded here from octez's `operation_repr.ml` and the node's
// forging is only accepted when it matches byte for byte. Nothing else is ever signed.
//
// Manager operation: tag | source (pkh: 1-byte curve tag + 20 bytes) | fee | counter | gas_limit |
// storage_limit (all unsigned zarith) | body. Bodies: reveal (107) = public key + optional proof;
// update_consensus_key (114) and update_companion_key (115) = public key + optional proof.
// Public key = 1-byte curve tag + raw key. Optional proof = 00, or ff + 4-byte length + BLS
// signature (96 bytes). The whole operation is branch (32 bytes) followed by the contents.

import { sha256 } from "@noble/hashes/sha2.js";

const TAGS = { reveal: 107, update_consensus_key: 114, update_companion_key: 115 };

// Base58 prefixes and binary tags from octez `base58.ml` / `signature_v4.ml`.
const PKH = {
  tz1: { prefix: [6, 161, 159], tag: 0 },
  tz2: { prefix: [6, 161, 161], tag: 1 },
  tz3: { prefix: [6, 161, 164], tag: 2 },
  tz4: { prefix: [6, 161, 166], tag: 3 },
  tz5: { prefix: [6, 161, 169], tag: 4 },
  tz6: { prefix: [6, 161, 171], tag: 5 },
};
const PK = {
  edpk: { prefix: [13, 15, 37, 217], tag: 0, length: 32 },
  sppk: { prefix: [3, 254, 226, 86], tag: 1, length: 33 },
  p2pk: { prefix: [3, 178, 139, 127], tag: 2, length: 33 },
  BLpk: { prefix: [6, 149, 135, 204], tag: 3, length: 48 },
  mdpk: { prefix: [13, 7, 237, 67], tag: 4, length: 1312 },
  xmpk: { prefix: [1, 121, 6, 180], tag: 5 },
};
const BLOCK_HASH = { prefix: [1, 52], length: 32 };
const BLS_SIGNATURE = { prefix: [40, 171, 64, 207], length: 96 };

const ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

function base58Decode(text) {
  const bytes = [0];
  for (const ch of text) {
    let carry = ALPHABET.indexOf(ch);
    if (carry < 0) throw new Error(`not base58: ${text}`);
    for (let i = 0; i < bytes.length; i++) {
      carry += bytes[i] * 58;
      bytes[i] = carry & 0xff;
      carry >>= 8;
    }
    while (carry > 0) { bytes.push(carry & 0xff); carry >>= 8; }
  }
  for (const ch of text) { if (ch === "1") bytes.push(0); else break; }
  return Uint8Array.from(bytes.reverse());
}

/** The payload of a base58check string after `prefix`, with checksum and prefix verified. */
function b58check(text, { prefix, length }) {
  const decoded = base58Decode(text);
  if (decoded.length < prefix.length + 4) throw new Error(`too short: ${text}`);
  const body = decoded.subarray(0, decoded.length - 4);
  const check = sha256(sha256(body)).subarray(0, 4);
  const given = decoded.subarray(decoded.length - 4);
  if (!check.every((b, i) => b === given[i])) throw new Error(`bad checksum: ${text}`);
  if (!prefix.every((b, i) => b === body[i])) throw new Error(`unexpected prefix: ${text}`);
  const payload = body.subarray(prefix.length);
  if (length !== undefined && payload.length !== length) throw new Error(`${text}: expected ${length} bytes, got ${payload.length}`);
  return payload;
}

const hex = (bytes) => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
const byte = (n) => n.toString(16).padStart(2, "0");
const u32 = (n) => n.toString(16).padStart(8, "0");

/** Unsigned zarith: 7 bits per byte, least significant first, high bit set while more follow. */
function zarith(value) {
  let n = BigInt(value);
  if (n < 0n) throw new Error(`negative amount ${value}`);
  let out = "";
  do {
    let b = Number(n & 0x7fn);
    n >>= 7n;
    if (n > 0n) b |= 0x80;
    out += byte(b);
  } while (n > 0n);
  return out;
}

function publicKeyHash(address) {
  const spec = PKH[address.slice(0, 3)];
  if (!spec) throw new Error(`unknown address kind ${address}`);
  return byte(spec.tag) + hex(b58check(address, { prefix: spec.prefix, length: 20 }));
}

/** Octez's binary public_key_hash (curve tag + 20 bytes) as hex, for `PUSH key_hash 0x…`. */
export const encodedPublicKeyHash = publicKeyHash;

const CONTRACT_HASH = { prefix: [2, 90, 121], length: 20 }; // KT1

/** Octez's binary address of an originated contract with its default entrypoint (01 + hash + 00), for `PUSH address 0x…`. */
export function encodedContractAddress(address) {
  if (!address.startsWith("KT1")) throw new Error(`not a contract address: ${address}`);
  return "01" + hex(b58check(address, CONTRACT_HASH)) + "00";
}

function publicKey(key) {
  const spec = PK[key.slice(0, 4)];
  if (!spec) throw new Error(`unknown public key kind ${key}`);
  return byte(spec.tag) + hex(b58check(key, spec));
}

function proof(sig) {
  if (!sig) return "00";
  const bytes = b58check(sig, BLS_SIGNATURE);
  return "ff" + u32(bytes.length) + hex(bytes);
}

function content(c) {
  const tag = TAGS[c.kind];
  if (tag === undefined) throw new Error(`Signet does not forge "${c.kind}" operations itself`);
  const header = byte(tag) + publicKeyHash(c.source) + zarith(c.fee) + zarith(c.counter) + zarith(c.gas_limit) + zarith(c.storage_limit);
  switch (c.kind) {
    case "reveal": return header + publicKey(c.public_key) + proof(c.proof);
    case "update_consensus_key":
    case "update_companion_key": return header + publicKey(c.pk) + proof(c.proof);
  }
}

/** Forges `contents` on `branch` exactly as the node would. Hex, unsigned. */
export function forgeRawOperation(branch, contents) {
  return hex(b58check(branch, BLOCK_HASH)) + contents.map(content).join("");
}

/**
 * Our forging of the operation, after checking the node's agrees. A difference means either the
 * node is lying or our encoder is wrong; either way nothing gets signed.
 */
export function verifyRawForging(branch, contents, nodeForged) {
  const local = forgeRawOperation(branch, contents);
  if (typeof nodeForged !== "string" || nodeForged.toLowerCase() !== local) {
    throw new Error("The node forged this operation differently from Signet; refusing to sign it. Check the node you are connected to.");
  }
  return local;
}
