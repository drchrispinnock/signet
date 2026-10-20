// TzEL (shielded tez) protocol primitives, written from `specs/spec.md` of trilitech/tzel
// and checked byte for byte against the shared cross-implementation vectors
// (`specs/ocaml_vectors/protocol_v1.json`) by `test/tzel-vectors.cjs`.
//
// Everything here is pure: no network, no storage, no randomness except where a caller passes
// coins in. Felts are 32-byte little-endian `Uint8Array`s with the top five bits cleared.
// Hashing is BLAKE2s-256, domain-separated by an 8-byte personalization where the spec says so.
// ML-KEM-768 and ChaCha20-Poly1305 come from the noble packages the bridge already ships for tz5.

import { blake2s } from "@noble/hashes/blake2.js";
import { bytesToHex, concatBytes, hexToBytes, utf8ToBytes } from "@noble/hashes/utils.js";
import { ml_kem768 } from "@noble/post-quantum/ml-kem.js";
import { chacha20poly1305 } from "@noble/ciphers/chacha.js";

export { bytesToHex, hexToBytes };

// ── Felts and tags ───────────────────────────────────────────────────────────────────────

export const FELT_BYTES = 32;

/// `felt_of_int(n)`: the integer in the low bytes, little-endian, zero-extended.
export function feltOfInt(n) {
  const out = new Uint8Array(FELT_BYTES);
  if (typeof n === "number" && Number.isInteger(n) && n >= 0 && n <= 0xffffffff) {
    out[0] = n & 0xff; out[1] = (n >>> 8) & 0xff; out[2] = (n >>> 16) & 0xff; out[3] = (n >>> 24) & 0xff;
    return out;
  }
  let v = BigInt(n);
  if (v < 0n) throw new Error("tzel: felt of a negative integer");
  for (let i = 0; i < FELT_BYTES && v > 0n; i++) { out[i] = Number(v & 0xffn); v >>= 8n; }
  if (v !== 0n) throw new Error("tzel: integer does not fit a felt");
  return out;
}

/// A domain tag: the label's UTF-8 bytes read as a big-endian integer, encoded as a felt, so the
/// bytes land reversed in the low positions (`"spend"` → `64 6e 65 70 73 00 …`). No hashing.
export function feltTag(label) {
  const bytes = utf8ToBytes(label);
  if (bytes.length > FELT_BYTES) throw new Error("tzel: tag too long");
  const out = new Uint8Array(FELT_BYTES);
  for (let i = 0; i < bytes.length; i++) out[i] = bytes[bytes.length - 1 - i];
  return out;
}

export function feltToBigInt(felt) {
  let v = 0n;
  for (let i = felt.length - 1; i >= 0; i--) v = (v << 8n) | BigInt(felt[i]);
  return v;
}

function u32le(n) {
  if (!Number.isInteger(n) || n < 0 || n > 0xffffffff) throw new Error("tzel: value is not a u32");
  return new Uint8Array([n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff]);
}

function u32be(n) {
  if (!Number.isInteger(n) || n < 0 || n > 0xffffffff) throw new Error("tzel: value is not a u32");
  return new Uint8Array([(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff]);
}

function u64le(n) {
  let v = BigInt(n);
  if (v < 0n || v > 0xffffffffffffffffn) throw new Error("tzel: value is not a u64");
  const out = new Uint8Array(8);
  for (let i = 0; i < 8; i++) { out[i] = Number(v & 0xffn); v >>= 8n; }
  return out;
}

function readU64le(bytes, offset) {
  let v = 0n;
  for (let i = 7; i >= 0; i--) v = (v << 8n) | BigInt(bytes[offset + i]);
  return v;
}

function felt(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length !== FELT_BYTES) throw new Error("tzel: not a felt");
  return bytes;
}

function truncate(hash) { hash[31] &= 0x07; return hash; }

// ── BLAKE2s ──────────────────────────────────────────────────────────────────────────────

/// Raw BLAKE2s-256, optionally personalized; not truncated (the detection and AEAD keys use it).
export function blake2sRaw(data, personal) {
  if (personal === undefined || personal === "") return blake2s(data);
  const personalization = utf8ToBytes(personal);
  if (personalization.length !== 8) throw new Error("tzel: personalization must be 8 bytes");
  return blake2s(data, { personalization });
}

/// `H(data)`: unpersonalized BLAKE2s truncated to 251 bits.
export function hash(data) { return truncate(blake2sRaw(data)); }

/// `H(a, b)`: the two felts concatenated, unpersonalized.
export function hashTwo(a, b) { return hash(concatBytes(felt(a), felt(b))); }

/// A personalized hash over the concatenation of its parts, truncated.
export function hashPersonal(personal, ...parts) { return truncate(blake2sRaw(concatBytes(...parts), personal)); }

export const hashMerkle = (left, right) => hashPersonal("mrklSP__", felt(left), felt(right));
export const sighashFold = (a, b) => hashPersonal("sighSP__", felt(a), felt(b));

/// `fold(x_0, …, x_n)`: the sequential left fold of `sighashFold`.
export function fold(items) {
  if (items.length === 0) throw new Error("tzel: fold of nothing");
  let acc = felt(items[0]);
  for (let i = 1; i < items.length; i++) acc = sighashFold(acc, items[i]);
  return acc;
}

/// `recipient_id` / account id: the canonical string's UTF-8 hashed, unpersonalized, truncated.
export function accountId(string) { return hash(utf8ToBytes(string)); }

// ── Key hierarchy ────────────────────────────────────────────────────────────────────────

export function deriveAccount(masterSk) {
  const spendSeed = hashTwo(feltTag("spend"), masterSk);
  return {
    nk: hashTwo(feltTag("nk"), spendSeed),
    askBase: hashTwo(feltTag("ask"), spendSeed),
    incomingSeed: hashTwo(feltTag("incoming"), masterSk),
    outgoingSeed: hashTwo(feltTag("outgoing"), masterSk),
  };
}

export const deriveDsk = (incomingSeed) => hashTwo(feltTag("dsk"), incomingSeed);
export const deriveDiversifier = (incomingSeed, j) => hashTwo(deriveDsk(incomingSeed), feltOfInt(j));
export const deriveAsk = (askBase, j) => hashTwo(askBase, feltOfInt(j));
export const deriveViewRoot = (incomingSeed) => hashTwo(feltTag("view"), incomingSeed);
export const deriveDetectRoot = (incomingSeed) => hashTwo(feltTag("detect"), deriveViewRoot(incomingSeed));
export const deriveNkSpend = (nk, dJ) => hashPersonal("nkspSP__", felt(nk), felt(dJ));
export const deriveNkTag = (nkSpend) => hashPersonal("nktgSP__", felt(nkSpend));
export const ownerTag = (authRoot, pubSeed, nkTag) => hashPersonal("ownrSP__", felt(authRoot), felt(pubSeed), felt(nkTag));

/// The 64-byte ML-KEM seed for address `j` from a view or detect root.
export function kemSeedFromRoot(kind, root, j) {
  const [tag1, tag2] = kind === "view" ? ["mlkem-v", "mlkem-v2"] : kind === "detect" ? ["mlkem-d", "mlkem-d2"] : [];
  if (!tag1) throw new Error("tzel: KEM seed kind must be view or detect");
  const h1 = hashTwo(feltTag(tag1), root);
  const h2 = hashTwo(h1, feltOfInt(j));
  return concatBytes(h2, hashTwo(feltTag(tag2), h2));
}

export const kemViewSeed = (incomingSeed, j) => kemSeedFromRoot("view", deriveViewRoot(incomingSeed), j);
export const kemDetectSeed = (incomingSeed, j) => kemSeedFromRoot("detect", deriveDetectRoot(incomingSeed), j);

/// FIPS 203 `KeyGen_internal(d, z)` from the 64-byte seed: `{ ek, dk }`.
export function kemKeygen(seed64) {
  if (seed64.length !== 64) throw new Error("tzel: KEM seed must be 64 bytes");
  const { publicKey, secretKey } = ml_kem768.keygen(seed64);
  return { ek: publicKey, dk: secretKey };
}

/// Deterministic encapsulation with explicit coins (random coins when omitted).
export function kemEncapsulate(ek, coins) {
  const { cipherText, sharedSecret } = coins ? ml_kem768.encapsulate(ek, coins) : ml_kem768.encapsulate(ek);
  return { ct: cipherText, ss: sharedSecret };
}

export const kemDecapsulate = (ct, dk) => ml_kem768.decapsulate(ct, dk);

// ── XMSS-style auth tree (WOTS+, w = 4, 133 chains, 65536 keys per address) ─────────────

export const AUTH_DEPTH = 16;
export const AUTH_TREE_SIZE = 1 << AUTH_DEPTH;
export const WOTS_W = 4;
export const WOTS_CHAINS = 133;
const TAG_XMSS_CHAIN = 0x0068632d73736d78n;
const TAG_XMSS_LTREE = 0x00746c2d73736d78n;
const TAG_XMSS_TREE = 0x0072742d73736d78n;

function writeU32(out, offset, n) {
  if (!Number.isInteger(n) || n < 0 || n > 0xffffffff) throw new Error("tzel: not a u32");
  out[offset] = n & 0xff; out[offset + 1] = (n >>> 8) & 0xff; out[offset + 2] = (n >>> 16) & 0xff; out[offset + 3] = (n >>> 24) & 0xff;
}

/// `pack(tag, key_idx, a, b, c)` as one felt.
export function packAdrs(tag, keyIdx, a, b, c) {
  const out = new Uint8Array(FELT_BYTES);
  let t = tag;
  for (let i = 0; i < 8; i++) { out[i] = Number(t & 0xffn); t >>= 8n; }
  writeU32(out, 8, keyIdx); writeU32(out, 12, a); writeU32(out, 16, b); writeU32(out, 20, c);
  out[31] &= 0x07;
  return out;
}

export const authKeySeed = (askJ, keyIdx) => hash(concatBytes(feltTag("xmss-sk"), felt(askJ), feltOfInt(keyIdx)));
export const deriveAuthPubSeed = (askJ) => hash(concatBytes(feltTag("xmss-ps"), felt(askJ)));
const scratch64 = new Uint8Array(64);
function wotsSkChain(keySeed, chainIdx) {
  scratch64.set(keySeed, 0);
  scratch64.fill(0, 32, 64);
  writeU32(scratch64, 32, chainIdx);
  return truncate(blake2s(scratch64));
}

// The auth tree is about 44 million hashes per address, so these three avoid allocating:
// each writes pub_seed, the packed ADRS and the inputs into one scratch buffer and hashes it.
const scratch96 = new Uint8Array(96);
const scratch128 = new Uint8Array(128);
const TAG_CHAIN_BYTES = packAdrs(TAG_XMSS_CHAIN, 0, 0, 0, 0).slice(0, 8);
const TAG_LTREE_BYTES = packAdrs(TAG_XMSS_LTREE, 0, 0, 0, 0).slice(0, 8);
const TAG_TREE_BYTES = packAdrs(TAG_XMSS_TREE, 0, 0, 0, 0).slice(0, 8);

function writeAdrs(buf, offset, tagBytes, keyIdx, a, b, c) {
  buf.set(tagBytes, offset);
  writeU32(buf, offset + 8, keyIdx); writeU32(buf, offset + 12, a); writeU32(buf, offset + 16, b); writeU32(buf, offset + 20, c);
  buf.fill(0, offset + 24, offset + 32);
}

function chainStep(x, pubSeed, keyIdx, chainIdx, step) {
  scratch96.set(pubSeed, 0);
  writeAdrs(scratch96, 32, TAG_CHAIN_BYTES, keyIdx, chainIdx, step, 0);
  scratch96.set(x, 64);
  return truncate(blake2s(scratch96));
}

function hashChain(x, pubSeed, keyIdx, chainIdx, start, steps) {
  let current = x;
  for (let step = start; step < start + steps; step++) current = chainStep(current, pubSeed, keyIdx, chainIdx, step);
  return current;
}

function ltreeNode(pubSeed, keyIdx, level, nodeIdx, left, right) {
  scratch128.set(pubSeed, 0);
  writeAdrs(scratch128, 32, TAG_LTREE_BYTES, keyIdx, level, nodeIdx, 0);
  scratch128.set(left, 64); scratch128.set(right, 96);
  return truncate(blake2s(scratch128));
}

export function xmssTreeNode(pubSeed, level, nodeIdx, left, right) {
  scratch128.set(pubSeed, 0);
  writeAdrs(scratch128, 32, TAG_TREE_BYTES, 0, level, nodeIdx, 0);
  scratch128.set(left, 64); scratch128.set(right, 96);
  return truncate(blake2s(scratch128));
}

/// The 133 base-4 digits of a message hash: 128 from its bytes, then 5 checksum digits.
export function wotsDigits(msgHash) {
  const digits = [];
  for (const byte of felt(msgHash)) { let b = byte; for (let k = 0; k < 4; k++) { digits.push(b & 3); b >>= 2; } }
  let checksum = 0;
  for (const d of digits) checksum += WOTS_W - 1 - d;
  for (let k = 0; k < 5; k++) { digits.push(checksum & 3); checksum >>= 2; }
  return digits.slice(0, WOTS_CHAINS);
}

/// The WOTS+ public key (133 chain endpoints) of key `keyIdx`.
export function wotsPk(askJ, pubSeed, keyIdx) {
  const keySeed = authKeySeed(askJ, keyIdx);
  const pk = new Array(WOTS_CHAINS);
  for (let c = 0; c < WOTS_CHAINS; c++) pk[c] = hashChain(wotsSkChain(keySeed, c), pubSeed, keyIdx, c, 0, WOTS_W - 1);
  return pk;
}

/// L-tree compression of the chain endpoints into the auth leaf.
export function wotsPkToLeaf(pubSeed, keyIdx, pk) {
  let current = pk.slice();
  let level = 0;
  while (current.length > 1) {
    const next = [];
    let nodeIdx = 0;
    for (let i = 0; i < current.length; i += 2) {
      if (i + 1 === current.length) next.push(current[i]);
      else { next.push(ltreeNode(pubSeed, keyIdx, level, nodeIdx, current[i], current[i + 1])); nodeIdx++; }
    }
    current = next;
    level++;
  }
  return current[0];
}

export const authLeaf = (askJ, pubSeed, keyIdx) => wotsPkToLeaf(pubSeed, keyIdx, wotsPk(askJ, pubSeed, keyIdx));

/// Sign a message hash with key `keyIdx`: 133 chain values. Each key index must be used once.
export function wotsSign(askJ, pubSeed, keyIdx, msgHash) {
  const keySeed = authKeySeed(askJ, keyIdx);
  const digits = wotsDigits(msgHash);
  const sig = new Array(WOTS_CHAINS);
  for (let c = 0; c < WOTS_CHAINS; c++) sig[c] = hashChain(wotsSkChain(keySeed, c), pubSeed, keyIdx, c, 0, digits[c]);
  return sig;
}

export function recoverWotsPk(msgHash, pubSeed, keyIdx, sig) {
  if (sig.length !== WOTS_CHAINS) throw new Error("tzel: bad WOTS+ signature length");
  const digits = wotsDigits(msgHash);
  return sig.map((part, c) => hashChain(part, pubSeed, keyIdx, c, digits[c], WOTS_W - 1 - digits[c]));
}

/// Every level of the auth tree, leaves first: `levels[0]` has 65536 leaves, `levels[16]` the root.
/// This is the expensive part (about 44 million hashes); `onProgress(done, total)` is called per
/// 1024 leaves so a caller can report. Keep the result: it is needed for every signature's path.
export function buildAuthTree(askJ, pubSeed, onProgress) {
  const leaves = new Array(AUTH_TREE_SIZE);
  for (let i = 0; i < AUTH_TREE_SIZE; i++) {
    leaves[i] = authLeaf(askJ, pubSeed, i);
    if (onProgress && (i & 1023) === 1023) onProgress(i + 1, AUTH_TREE_SIZE);
  }
  return authTreeLevels(pubSeed, leaves);
}

export function authTreeLevels(pubSeed, leaves) {
  if (leaves.length !== AUTH_TREE_SIZE) throw new Error("tzel: an auth tree has 65536 leaves");
  const levels = [leaves];
  for (let level = 0; level < AUTH_DEPTH; level++) {
    const below = levels[level];
    const above = new Array(below.length / 2);
    for (let i = 0; i < above.length; i++) above[i] = xmssTreeNode(pubSeed, level, i, below[2 * i], below[2 * i + 1]);
    levels.push(above);
  }
  return levels;
}

export const authRootOf = (levels) => levels[AUTH_DEPTH][0];

/// The sibling path of leaf `index`, leaf level first.
export function authPath(levels, index) {
  if (!Number.isInteger(index) || index < 0 || index >= AUTH_TREE_SIZE) throw new Error("tzel: auth key index out of range");
  const path = [];
  for (let level = 0; level < AUTH_DEPTH; level++) path.push(levels[level][(index >> level) ^ 1]);
  return path;
}

// ── Commitment tree (depth 48, `mrklSP__`) ───────────────────────────────────────────────

export const TREE_DEPTH = 48;

export function merkleZeros(depth) {
  const zeros = [new Uint8Array(FELT_BYTES)];
  for (let d = 0; d < depth; d++) zeros.push(hashMerkle(zeros[d], zeros[d]));
  return zeros;
}

/// Root of an append-only tree of `depth` holding `leaves` from position 0; missing leaves are zero.
export function merkleRoot(leaves, depth) {
  const zeros = merkleZeros(depth);
  let level = leaves.map(felt);
  for (let d = 0; d < depth; d++) {
    const next = [];
    for (let i = 0; i < level.length; i += 2) next.push(hashMerkle(level[i], i + 1 < level.length ? level[i + 1] : zeros[d]));
    level = next;
  }
  return level.length ? level[0] : zeros[depth];
}

/// The sibling path of leaf `index` (leaf level first) in the same tree.
export function merklePath(leaves, depth, index) {
  if (!Number.isInteger(index) || index < 0 || index >= leaves.length) throw new Error("tzel: leaf index out of range");
  const zeros = merkleZeros(depth);
  const path = [];
  let level = leaves.map(felt);
  let pos = index;
  for (let d = 0; d < depth; d++) {
    const sibling = pos ^ 1;
    path.push(sibling < level.length ? level[sibling] : zeros[d]);
    const next = [];
    for (let i = 0; i < level.length; i += 2) next.push(hashMerkle(level[i], i + 1 < level.length ? level[i + 1] : zeros[d]));
    level = next;
    pos >>= 1;
  }
  return path;
}

// ── Notes ────────────────────────────────────────────────────────────────────────────────

export const MEMO_SIZE = 1024;
export const DETECT_K = 10;
export const NOTE_LAYOUT = Object.freeze({ ctD: 1088, tag: 2, ctV: 1088, nonce: 12, encryptedData: 8 + 32 + MEMO_SIZE + 16, outgoingCt: 1 + 8 + 5 * 32 + 16 });
export const ENCRYPTED_NOTE_BYTES = 1088 + 2 + 1088 + 12 + 1080 + 185; // 3455
export const PAYMENT_ADDRESS_BYTES = 4 * FELT_BYTES + 2 * 1184; // 2496

export const deriveRcm = (rseed) => hashTwo(hash(feltTag("rcm")), rseed);

export function commit(dJ, v, rcm, otag) {
  const buf = new Uint8Array(128);
  buf.set(felt(dJ), 0);
  buf.set(u64le(v), 32);
  buf.set(felt(rcm), 64);
  buf.set(felt(otag), 96);
  return hashPersonal("cmmtSP__", buf);
}

export function nullifier(nkSpend, cm, pos) {
  const cmPos = hashPersonal("nulfSP__", felt(cm), feltOfInt(pos));
  return hashPersonal("nulfSP__", felt(nkSpend), cmPos);
}

/// `{ d_j, auth_root, pub_seed, nk_tag, ek_v, ek_d }` ⇄ the 2496-byte canonical record.
export function encodePaymentAddress(a) {
  if (a.ekV.length !== 1184 || a.ekD.length !== 1184) throw new Error("tzel: ML-KEM keys are 1184 bytes");
  return concatBytes(felt(a.dJ), felt(a.authRoot), felt(a.pubSeed), felt(a.nkTag), a.ekV, a.ekD);
}

export function decodePaymentAddress(bytes) {
  if (bytes.length !== PAYMENT_ADDRESS_BYTES) throw new Error("tzel: a payment address is 2496 bytes");
  return { dJ: bytes.slice(0, 32), authRoot: bytes.slice(32, 64), pubSeed: bytes.slice(64, 96), nkTag: bytes.slice(96, 128), ekV: bytes.slice(128, 1312), ekD: bytes.slice(1312, 2496) };
}

/// The reference JSON form of a payment address (lowercase hex fields) ⇄ ours.
export function paymentAddressFromJSON(json) {
  const need = (k, n) => { const v = hexToBytes(String(json[k] ?? "")); if (v.length !== n) throw new Error(`tzel: payment address field ${k} must be ${n} bytes`); return v; };
  return { dJ: need("d_j", 32), authRoot: need("auth_root", 32), pubSeed: need("auth_pub_seed", 32), nkTag: need("nk_tag", 32), ekV: need("ek_v", 1184), ekD: need("ek_d", 1184) };
}

export function paymentAddressToJSON(a) {
  return { d_j: bytesToHex(a.dJ), auth_root: bytesToHex(a.authRoot), auth_pub_seed: bytesToHex(a.pubSeed), nk_tag: bytesToHex(a.nkTag), ek_v: bytesToHex(a.ekV), ek_d: bytesToHex(a.ekD) };
}

export function encodeEncryptedNote(enc) {
  const L = NOTE_LAYOUT;
  if (enc.ctD.length !== L.ctD || enc.ctV.length !== L.ctV || enc.nonce.length !== L.nonce || enc.encryptedData.length !== L.encryptedData || enc.outgoingCt.length !== L.outgoingCt) throw new Error("tzel: malformed encrypted note");
  if (!Number.isInteger(enc.tag) || enc.tag < 0 || enc.tag > 0xffff) throw new Error("tzel: note tag is a u16");
  return concatBytes(enc.ctD, new Uint8Array([enc.tag & 0xff, enc.tag >>> 8]), enc.ctV, enc.nonce, enc.encryptedData, enc.outgoingCt);
}

export function decodeEncryptedNote(bytes) {
  if (bytes.length !== ENCRYPTED_NOTE_BYTES) throw new Error(`tzel: an encrypted note is ${ENCRYPTED_NOTE_BYTES} bytes, got ${bytes.length}`);
  const L = NOTE_LAYOUT;
  let o = 0;
  const take = (n) => { const v = bytes.slice(o, o + n); o += n; return v; };
  const ctD = take(L.ctD);
  const tagBytes = take(L.tag);
  const enc = { ctD, tag: tagBytes[0] | (tagBytes[1] << 8), ctV: take(L.ctV), nonce: take(L.nonce), encryptedData: take(L.encryptedData), outgoingCt: take(L.outgoingCt) };
  if (enc.tag >= 1 << DETECT_K) throw new Error("tzel: note tag has bits above the detection width");
  return enc;
}

export const encodePublishedNote = (cm, enc) => concatBytes(felt(cm), encodeEncryptedNote(enc));

export function decodePublishedNote(bytes) {
  if (bytes.length !== FELT_BYTES + ENCRYPTED_NOTE_BYTES) throw new Error(`tzel: a published note is ${FELT_BYTES + ENCRYPTED_NOTE_BYTES} bytes, got ${bytes.length}`);
  return { cm: bytes.slice(0, FELT_BYTES), enc: decodeEncryptedNote(bytes.slice(FELT_BYTES)) };
}

export const encodeNoteMemo = (index, cm, enc) => concatBytes(u64le(index), felt(cm), encodeEncryptedNote(enc));

export function decodeNoteMemo(bytes) {
  if (bytes.length !== 8 + FELT_BYTES + ENCRYPTED_NOTE_BYTES) throw new Error(`tzel: a note memo is ${8 + FELT_BYTES + ENCRYPTED_NOTE_BYTES} bytes, got ${bytes.length}`);
  return { index: readU64le(bytes, 0), cm: bytes.slice(8, 8 + FELT_BYTES), enc: decodeEncryptedNote(bytes.slice(8 + FELT_BYTES)) };
}

export const memoCtHash = (enc) => hashPersonal("memoSP__", encodeEncryptedNote(enc));

/// The low `DETECT_K` bits of the first two bytes of `H(ss_d)`.
export function detectionTag(ssD) {
  const h = hash(ssD);
  return (h[0] | (h[1] << 8)) & ((1 << DETECT_K) - 1);
}

export const noteAeadKey = (ssV) => hash(ssV);
export const noteAeadNonce = (key, plaintext) => blake2sRaw(concatBytes(key, plaintext), "mnonSP__").slice(0, 12);

/// The 1024-byte memo field: UTF-8 text zero-padded, or `0xF6` + zeros for none.
export function memoBytes(text) {
  const out = new Uint8Array(MEMO_SIZE);
  if (text === undefined || text === null || text === "") { out[0] = 0xf6; return out; }
  const bytes = text instanceof Uint8Array ? text : utf8ToBytes(text);
  if (bytes.length > MEMO_SIZE) throw new Error("tzel: memo longer than 1024 bytes");
  out.set(bytes);
  return out;
}

export function memoText(memo) {
  if (memo[0] === 0xf6) return "";
  if (memo[0] > 0xf4) return null;
  let end = memo.length;
  while (end > 0 && memo[end - 1] === 0) end--;
  try { return new TextDecoder("utf-8", { fatal: true }).decode(memo.slice(0, end)); } catch { return null; }
}

/// Encrypt a note to a payment address; `coins` (`{ d, v }`, 32 bytes each) make it deterministic.
export function encryptNote(v, rseed, memo, ekV, ekD, coins) {
  const { ct: ctD, ss: ssD } = kemEncapsulate(ekD, coins?.d);
  const tag = detectionTag(ssD);
  const plaintext = concatBytes(u64le(v), felt(rseed), memoBytes(memo));
  const { ct: ctV, ss: ssV } = kemEncapsulate(ekV, coins?.v);
  const key = noteAeadKey(ssV);
  const nonce = noteAeadNonce(key, plaintext);
  const encryptedData = chacha20poly1305(key, nonce).encrypt(plaintext);
  return { ctD, tag, ctV, nonce, encryptedData, outgoingCt: new Uint8Array(NOTE_LAYOUT.outgoingCt) };
}

/// Does the detection ciphertext match under this detection key? (2^-10 false positives.)
export function detect(enc, dkD) {
  return detectionTag(kemDecapsulate(enc.ctD, dkD)) === enc.tag;
}

/// `{ v, rseed, memo }` when the viewing key opens the note, else `null`.
export function decryptMemo(enc, dkV) {
  const key = noteAeadKey(kemDecapsulate(enc.ctV, dkV));
  let plaintext;
  try { plaintext = chacha20poly1305(key, enc.nonce).decrypt(enc.encryptedData); } catch { return null; }
  if (plaintext.length !== 8 + 32 + MEMO_SIZE) return null;
  return { v: readU64le(plaintext, 0), rseed: plaintext.slice(8, 40), memo: plaintext.slice(40) };
}

/// Outgoing note roles and their byte on the wire (the reference numbers them from 1).
export const OUTGOING_ROLES = Object.freeze({ shield_output: 1, producer_fee: 2, transfer_recipient: 3, transfer_change: 4, unshield_change: 5 });
const roleNames = Object.fromEntries(Object.entries(OUTGOING_ROLES).map(([name, byte]) => [byte, name]));

export function outgoingRecoveryPlaintext(p) {
  const role = OUTGOING_ROLES[p.role];
  if (!role) throw new Error("tzel: unknown outgoing note role");
  return concatBytes(new Uint8Array([role]), u64le(p.v), felt(p.rseed), felt(p.dJ), felt(p.authRoot), felt(p.pubSeed), felt(p.nkTag));
}

const outgoingKey = (outgoingSeed, cm) => hashPersonal("ovkKSP__", felt(outgoingSeed), felt(cm));
const outgoingNonce = (key, cm) => hashPersonal("ovkNSP__", key, felt(cm)).slice(0, 12);

export function encryptOutgoingRecovery(outgoingSeed, cm, plaintext) {
  const key = outgoingKey(outgoingSeed, cm);
  return chacha20poly1305(key, outgoingNonce(key, cm)).encrypt(outgoingRecoveryPlaintext(plaintext));
}

/// The sender's own record of an output it created, or `null` when it is not ours.
export function decryptOutgoingRecovery(outgoingSeed, cm, outgoingCt) {
  if (outgoingCt.length !== NOTE_LAYOUT.outgoingCt) return null;
  const key = outgoingKey(outgoingSeed, cm);
  let p;
  try { p = chacha20poly1305(key, outgoingNonce(key, cm)).decrypt(outgoingCt); } catch { return null; }
  if (p.length !== 1 + 8 + 5 * 32 || !roleNames[p[0]]) return null;
  return { role: roleNames[p[0]], v: readU64le(p, 1), rseed: p.slice(9, 41), dJ: p.slice(41, 73), authRoot: p.slice(73, 105), pubSeed: p.slice(105, 137), nkTag: p.slice(137, 169) };
}

/// Note acceptance (spec § Wallet Note Acceptance): a decrypted note is ours only when the
/// commitment recomputed from our address record equals the one on chain.
export function acceptsNote(address, cm, decrypted) {
  const expected = commit(address.dJ, decrypted.v, deriveRcm(decrypted.rseed), ownerTag(address.authRoot, address.pubSeed, address.nkTag));
  return bytesToHex(expected) === bytesToHex(cm);
}

// ── Deposit pools ────────────────────────────────────────────────────────────────────────

/// `pubkey_hash = fold(0x04, auth_domain, auth_root, pub_seed, blind)`.
export const depositPubkeyHash = (authDomain, authRoot, pubSeed, blind) => fold([feltOfInt(4), authDomain, authRoot, pubSeed, blind]);
export const depositRecipient = (pubkeyHash) => `deposit:${bytesToHex(felt(pubkeyHash))}`;

/// The durable-state key holding a pool's balance.
export const depositBalanceKey = (pubkeyHash) => `/tzel/v1/state/deposits/balance/${bytesToHex(felt(pubkeyHash))}`;

// ── Shield (public → private) ────────────────────────────────────────────────────────────
//
// A shield drains a deposit pool into a note the pool's own auth tree owns. The wallet picks the
// value and fees at shield time, builds the recipient note (to itself) and the producer-fee note
// (to the DAL slot producer), signs the shield sighash with the next WOTS+ key of the address and
// proves it; the kernel checks the proof's public outputs against the request fields.

/// A fresh 251-bit value from the platform's randomness.
export function randomFelt() {
  const out = new Uint8Array(FELT_BYTES);
  crypto.getRandomValues(out);
  return truncate(out);
}

/// The per-pool blind, derived as the reference wallet does so that the same seed and counters
/// name the same pools: `H("tzel-deposit-blind" ‖ master_sk ‖ u32le(address) ‖ u64le(nonce))`.
export const depositBlind = (masterSk, addressIndex, nonce) =>
  hash(concatBytes(utf8ToBytes("tzel-deposit-blind"), felt(masterSk), u32le(addressIndex), u64le(nonce)));

/// `fold(0x03, auth_domain, pubkey_hash, v, fee, producer_fee, cm_new, cm_producer, mh_new, mh_producer)`.
export function shieldSighash(p) {
  return fold([feltOfInt(3), felt(p.authDomain), felt(p.pubkeyHash), feltOfInt(p.v), feltOfInt(p.fee), feltOfInt(p.producerFee),
               felt(p.cmRecipient), felt(p.cmProducer), felt(p.mhRecipient), felt(p.mhProducer)]);
}

/// An output note to `address` for `v` mutez: commitment, encrypted note (with the sender's
/// outgoing-recovery record when `outgoing` is `{ seed, role }`), memo hash and the rseed used.
/// `rseed` and `coins` are random unless given (tests).
export function buildOutputNote(address, v, memo, outgoing, rseed, coins) {
  const seed = rseed ?? randomFelt();
  const otag = ownerTag(address.authRoot, address.pubSeed, address.nkTag);
  const cm = commit(address.dJ, v, deriveRcm(seed), otag);
  const enc = encryptNote(v, seed, memo, address.ekV, address.ekD, coins);
  if (outgoing) {
    enc.outgoingCt = encryptOutgoingRecovery(outgoing.seed, cm, { role: outgoing.role, v, rseed: seed, dJ: address.dJ, authRoot: address.authRoot, pubSeed: address.pubSeed, nkTag: address.nkTag });
  }
  return { cm, enc, mh: memoCtHash(enc), rseed: seed };
}

/// A felt as the Cairo runner's hex argument: big-endian, no leading zeros, `0x0` for zero.
export function feltHex(f) {
  const h = feltToBigInt(felt(f)).toString(16);
  return "0x" + (h === "0" ? "0" : h);
}

export const intHex = (n) => "0x" + BigInt(n).toString(16);

/// The `run_shield` witness in the proving service's `arguments` layout (the reference wallet's
/// convention; a length word, then 16 fixed felts, the 133 signature chains, the 16 auth-path
/// siblings and the 5 producer-address fields).
export function shieldWitness(p) {
  const sig = p.signature, path = p.authPath;
  if (sig.length !== WOTS_CHAINS) throw new Error("tzel: shield witness needs the 133 signature chains");
  if (path.length !== AUTH_DEPTH) throw new Error("tzel: shield witness needs the 16 auth-path siblings");
  const fields = [
    p.authDomain, p.pubkeyHash, feltOfInt(p.v), feltOfInt(p.fee), feltOfInt(p.producerFee),
    p.recipientNote.cm, p.producerNote.cm, p.recipientNote.mh, p.producerNote.mh,
    p.recipient.authRoot, p.recipient.pubSeed, p.recipient.nkTag, p.recipient.dJ, p.recipientNote.rseed, p.blind, feltOfInt(p.keyIdx),
    ...sig, ...path,
    p.producer.authRoot, p.producer.pubSeed, p.producer.nkTag, p.producer.dJ, p.producerNote.rseed,
  ];
  if (fields.length !== 16 + WOTS_CHAINS + AUTH_DEPTH + 5) throw new Error("tzel: shield witness has the wrong length");
  return [intHex(fields.length), ...fields.map(feltHex)];
}

/// The auth root a leaf and its sibling path lead to.
export function authRootFromPath(pubSeed, leaf, index, path) {
  if (path.length !== AUTH_DEPTH) throw new Error("tzel: an auth path has 16 siblings");
  let node = felt(leaf);
  for (let level = 0; level < AUTH_DEPTH; level++) {
    const idx = index >> level;
    node = (idx & 1) === 0 ? xmssTreeNode(pubSeed, level, idx >> 1, node, path[level]) : xmssTreeNode(pubSeed, level, idx >> 1, path[level], node);
  }
  return node;
}

// ── Kernel inbox wire (`kernel_wire.rs`, version 17) ─────────────────────────────────────
//
// What the operator relays to the rollup: `version u16le ‖ tag u8 ‖ body`. A shield body is
// `pubkey_hash ‖ fee ‖ v ‖ producer_fee ‖ proof ‖ client_cm ‖ client_enc ‖ producer_cm ‖
// producer_enc`, where the u64s are little-endian, notes are the canonical 3455-byte record, and
// the proof is a length-prefixed (u32 big-endian) wrapper around
// `u32be(len) ‖ proof_bytes ‖ u32be(count) ‖ output felts`.

export const KERNEL_WIRE_VERSION = 17;
export const KERNEL_SHIELD_TAG = 2;
export const MAX_PROOF_BYTES = 8 * 1024 * 1024;
export const MAX_OUTPUT_PREIMAGE_ITEMS = 1024;

export function encodeStarkProof(proofBytes, outputPreimage) {
  if (proofBytes.length > MAX_PROOF_BYTES) throw new Error("tzel: proof too large for the kernel wire");
  if (outputPreimage.length > MAX_OUTPUT_PREIMAGE_ITEMS) throw new Error("tzel: too many public outputs for the kernel wire");
  return concatBytes(u32be(proofBytes.length), proofBytes, u32be(outputPreimage.length), ...outputPreimage.map(felt));
}

export function encodeShieldMessage(m) {
  const proof = encodeStarkProof(m.proofBytes, m.outputPreimage);
  return concatBytes(
    new Uint8Array([KERNEL_WIRE_VERSION & 0xff, KERNEL_WIRE_VERSION >>> 8, KERNEL_SHIELD_TAG]),
    felt(m.pubkeyHash), u64le(m.fee), u64le(m.v), u64le(m.producerFee),
    u32be(proof.length), proof,
    felt(m.clientCm), encodeEncryptedNote(m.clientEnc), felt(m.producerCm), encodeEncryptedNote(m.producerEnc),
  );
}

// ── Unshield (private → public) ──────────────────────────────────────────────────────────
//
// An unshield spends one to seven of the wallet's notes: `v_pub` mutez leave for a layer 1
// account through the rollup's outbox (the ticketer's `burn`, executable once the commitment
// covering it is cemented), the rollup's fee is burnt, a note pays the DAL producer, and any
// change comes back as a note to a fresh address of ours. Each input is authorised by a WOTS+
// signature over the one sighash from its address's auth tree and shown to be in the commitment
// tree under `root`.

export const MAX_UNSHIELD_INPUTS = 7;

/// `fold(0x02, auth_domain, root, nf_0 … nf_{n-1}, v_pub, fee, recipient_id, cm_change, mh_change, cm_fee, mh_fee)`.
export function unshieldSighash(p) {
  if (p.nullifiers.length === 0 || p.nullifiers.length > MAX_UNSHIELD_INPUTS) throw new Error("tzel: an unshield spends one to seven notes");
  return fold([feltOfInt(2), felt(p.authDomain), felt(p.root), ...p.nullifiers.map(felt), feltOfInt(p.vPub), feltOfInt(p.fee), felt(p.recipientId),
               felt(p.cmChange), felt(p.mhChange), felt(p.cmFee), felt(p.mhFee)]);
}

/// The `run_unshield` witness (`cairo/src/run_unshield.cairo`): a length word, then `n`, the five
/// fixed felts, nine felts per input, the 48 commitment-path siblings per input, the 16 auth-path
/// siblings per input, the 133 signature chains per input, the change note (a flag and seven
/// fields, zeros when there is none) and the producer-fee note's seven fields.
export function unshieldWitness(p) {
  const n = p.inputs.length;
  if (n === 0 || n > MAX_UNSHIELD_INPUTS) throw new Error("tzel: an unshield spends one to seven notes");
  const fields = [feltOfInt(n), p.authDomain, p.root, feltOfInt(p.vPub), feltOfInt(p.fee), p.recipientId];
  for (const i of p.inputs) fields.push(i.nullifier, i.nkSpend, i.address.authRoot, i.address.pubSeed, feltOfInt(i.keyIdx), i.address.dJ, feltOfInt(i.v), i.rseed, feltOfInt(i.index));
  for (const i of p.inputs) {
    if (i.cmPath.length !== TREE_DEPTH) throw new Error("tzel: an unshield input needs its 48 commitment-path siblings");
    fields.push(...i.cmPath);
  }
  for (const i of p.inputs) {
    if (i.authPath.length !== AUTH_DEPTH) throw new Error("tzel: an unshield input needs its 16 auth-path siblings");
    fields.push(...i.authPath);
  }
  for (const i of p.inputs) {
    if (i.signature.length !== WOTS_CHAINS) throw new Error("tzel: an unshield input needs its 133 signature chains");
    fields.push(...i.signature);
  }
  if (p.change) {
    fields.push(feltOfInt(1), p.change.address.dJ, feltOfInt(p.change.v), p.change.note.rseed, p.change.address.authRoot, p.change.address.pubSeed, p.change.address.nkTag, p.change.note.mh);
  } else {
    for (let i = 0; i < 8; i++) fields.push(feltOfInt(0));
  }
  fields.push(p.producer.dJ, feltOfInt(p.producerFee), p.producerNote.rseed, p.producer.authRoot, p.producer.pubSeed, p.producer.nkTag, p.producerNote.mh);
  if (fields.length !== 6 + n * (9 + TREE_DEPTH + AUTH_DEPTH + WOTS_CHAINS) + 15) throw new Error("tzel: unshield witness has the wrong length");
  return [intHex(fields.length), ...fields.map(feltHex)];
}

// An unshield body on the kernel wire (tag 4) is itself length-prefixed: `root ‖ nullifiers ‖
// v_pub ‖ fee ‖ recipient ‖ cm_change ‖ proof ‖ change note? ‖ cm_fee ‖ fee note`. The nullifier
// list is `u32be(36n) ‖ (u32be(32) ‖ felt)×n`, the recipient is `u32be(len) ‖ UTF-8`, each note
// is `u32be(3455) ‖ record`, and the optional change note is `0x00` or `0xff ‖ note`.

export const KERNEL_UNSHIELD_TAG = 4;
export const MAX_ACCOUNT_ID_BYTES = 1024;

function encodeFeltList(felts) {
  return concatBytes(u32be(felts.length * (4 + FELT_BYTES)), ...felts.flatMap((f) => [u32be(FELT_BYTES), felt(f)]));
}

export function encodeUnshieldMessage(m) {
  const recipient = utf8ToBytes(m.recipient);
  if (recipient.length === 0 || recipient.length > MAX_ACCOUNT_ID_BYTES) throw new Error("tzel: bad recipient length for the kernel wire");
  if (m.nullifiers.length === 0 || m.nullifiers.length > MAX_UNSHIELD_INPUTS) throw new Error("tzel: an unshield spends one to seven notes");
  const proof = encodeStarkProof(m.proofBytes, m.outputPreimage);
  const feeNote = encodeEncryptedNote(m.producerEnc);
  let change = new Uint8Array([0x00]);
  if (m.changeEnc) {
    const note = encodeEncryptedNote(m.changeEnc);
    change = concatBytes(new Uint8Array([0xff]), u32be(note.length), note);
  }
  const body = concatBytes(
    felt(m.root), encodeFeltList(m.nullifiers), u64le(m.vPub), u64le(m.fee), u32be(recipient.length), recipient, felt(m.cmChange),
    u32be(proof.length), proof, change, felt(m.cmFee), u32be(feeNote.length), feeNote,
  );
  return concatBytes(new Uint8Array([KERNEL_WIRE_VERSION & 0xff, KERNEL_WIRE_VERSION >>> 8, KERNEL_UNSHIELD_TAG]), u32be(body.length), body);
}

// ── Transfer (private → private) ─────────────────────────────────────────────────────────
//
// A transfer spends one to seven notes into exactly three: the recipient's, our change (to a
// fresh address, zero when there is none) and the producer fee's. The recipient is nothing but
// a payment address, the 2496-byte record above; there is no short form of it in the protocol,
// so wallets exchange the JSON and compare a fingerprint, the hash of the canonical bytes.

export const paymentAddressFingerprint = (a) => hash(encodePaymentAddress(a));

/// `fold(0x01, auth_domain, root, nf_0 … nf_{n-1}, fee, cm_1, cm_2, cm_3, mh_1, mh_2, mh_3)`.
export function transferSighash(p) {
  if (p.nullifiers.length === 0 || p.nullifiers.length > MAX_UNSHIELD_INPUTS) throw new Error("tzel: a transfer spends one to seven notes");
  return fold([feltOfInt(1), felt(p.authDomain), felt(p.root), ...p.nullifiers.map(felt), feltOfInt(p.fee),
               felt(p.outputs[0].cm), felt(p.outputs[1].cm), felt(p.outputs[2].cm), felt(p.outputs[0].mh), felt(p.outputs[1].mh), felt(p.outputs[2].mh)]);
}

/// The `run_transfer` witness (`cairo/src/run_transfer.cairo`): a length word, `n`, the three
/// fixed felts, the inputs as for an unshield, then the three outputs as `cm, d_j, v, rseed,
/// auth_root, auth_pub_seed, nk_tag, mh`.
export function transferWitness(p) {
  const n = p.inputs.length;
  if (n === 0 || n > MAX_UNSHIELD_INPUTS) throw new Error("tzel: a transfer spends one to seven notes");
  if (p.outputs.length !== 3) throw new Error("tzel: a transfer makes three notes");
  const fields = [feltOfInt(n), p.authDomain, p.root, feltOfInt(p.fee)];
  for (const i of p.inputs) fields.push(i.nullifier, i.nkSpend, i.address.authRoot, i.address.pubSeed, feltOfInt(i.keyIdx), i.address.dJ, feltOfInt(i.v), i.rseed, feltOfInt(i.index));
  for (const i of p.inputs) {
    if (i.cmPath.length !== TREE_DEPTH) throw new Error("tzel: a transfer input needs its 48 commitment-path siblings");
    fields.push(...i.cmPath);
  }
  for (const i of p.inputs) {
    if (i.authPath.length !== AUTH_DEPTH) throw new Error("tzel: a transfer input needs its 16 auth-path siblings");
    fields.push(...i.authPath);
  }
  for (const i of p.inputs) {
    if (i.signature.length !== WOTS_CHAINS) throw new Error("tzel: a transfer input needs its 133 signature chains");
    fields.push(...i.signature);
  }
  for (const o of p.outputs) fields.push(o.note.cm, o.address.dJ, feltOfInt(o.v), o.note.rseed, o.address.authRoot, o.address.pubSeed, o.address.nkTag, o.note.mh);
  if (fields.length !== 4 + n * (9 + TREE_DEPTH + AUTH_DEPTH + WOTS_CHAINS) + 24) throw new Error("tzel: transfer witness has the wrong length");
  return [intHex(fields.length), ...fields.map(feltHex)];
}

// A transfer body on the kernel wire (tag 3), length-prefixed like an unshield's: `root ‖
// nullifiers ‖ fee ‖ cm_1 ‖ cm_2 ‖ cm_3 ‖ proof ‖ note_1 ‖ note_2 ‖ note_3`.

export const KERNEL_TRANSFER_TAG = 3;

export function encodeTransferMessage(m) {
  if (m.nullifiers.length === 0 || m.nullifiers.length > MAX_UNSHIELD_INPUTS) throw new Error("tzel: a transfer spends one to seven notes");
  if (m.cms.length !== 3 || m.encs.length !== 3) throw new Error("tzel: a transfer carries three notes");
  const proof = encodeStarkProof(m.proofBytes, m.outputPreimage);
  const notes = m.encs.map(encodeEncryptedNote);
  const body = concatBytes(
    felt(m.root), encodeFeltList(m.nullifiers), u64le(m.fee), ...m.cms.map(felt),
    u32be(proof.length), proof, ...notes.flatMap((n) => [u32be(n.length), n]),
  );
  return concatBytes(new Uint8Array([KERNEL_WIRE_VERSION & 0xff, KERNEL_WIRE_VERSION >>> 8, KERNEL_TRANSFER_TAG]), u32be(body.length), body);
}
