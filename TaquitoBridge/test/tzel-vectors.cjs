// Offline check of src/tzel.js against the TzEL cross-implementation vectors
// (`specs/ocaml_vectors/protocol_v1.json` in trilitech/tzel). The vector file is not
// redistributable, so it is read from a tzel checkout: `TZEL_VECTORS=<path>` or the sibling
// clone at ../../tzel. Without one the test is skipped and says so.
//
// Every section of `specs/ocaml_vectors/test_vector_spec.md` is recomputed from the inputs it
// names and compared byte for byte. The three full auth roots (65536 WOTS+ leaves each) take a
// while in JavaScript, so they are checked only with `TZEL_FULL=1`.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const crypto = require('node:crypto');
const { build } = require('esbuild');

async function load(file) {
  const source = fs.readFileSync(path.resolve(__dirname, '../src', file), 'utf8');
  const result = await build({ stdin: { contents: source, resolveDir: path.resolve(__dirname, '../src'), sourcefile: file }, bundle: true, write: false, format: 'iife', globalName: 'API', platform: 'browser', target: 'safari17' });
  const context = { console, TextEncoder, TextDecoder, crypto: crypto.webcrypto };
  vm.createContext(context); vm.runInContext(result.outputFiles[0].text, context); return context.API;
}

const vectorsPath = process.env.TZEL_VECTORS || path.resolve(__dirname, '../../../tzel/specs/ocaml_vectors/protocol_v1.json');
if (!fs.existsSync(vectorsPath)) {
  console.log(`tzel vectors: skipped (no vector file at ${vectorsPath}; set TZEL_VECTORS)`);
  process.exit(0);
}
const V = JSON.parse(fs.readFileSync(vectorsPath, 'utf8'));

(async () => {
  const T = await load('tzel.js');
  const hex = (b) => T.bytesToHex(b);
  const bytes = (h) => T.hexToBytes(h);
  const eq = (actual, expected, what) => assert.equal(typeof actual === 'string' ? actual : hex(actual), expected, what);
  const felt = (n) => T.feltOfInt(n);
  const H = (s) => T.hash(new TextEncoder().encode(s));
  let checks = 0;
  const tick = () => { checks++; };

  // blake2s: raw outputs, not truncated.
  for (const [i, c] of V.blake2s.entries()) { eq(T.blake2sRaw(bytes(c.input), c.personal), c.output, `blake2s #${i}`); tick(); }

  // Domain tags are reversed label bytes.
  eq(T.feltTag('spend'), '646e657073000000000000000000000000000000000000000000000000000000', 'TAG_SPEND'); tick();
  eq(T.feltTag('mlkem-d2'), '32642d6d656b6c6d000000000000000000000000000000000000000000000000', 'TAG_MLKEM_D2'); tick();
  eq(T.feltTag('xmss-tr'), '72742d73736d7800000000000000000000000000000000000000000000000000', 'TAG_XMSS_TREE'); tick();

  // key_hierarchy
  const K = V.key_hierarchy;
  const masterSk = bytes(K.master_sk);
  eq(masterSk, hex(felt(12345)), 'master_sk is felt_of_int(12345)'); tick();
  const account = T.deriveAccount(masterSk);
  eq(account.nk, K.nk, 'nk'); eq(account.askBase, K.ask_base, 'ask_base'); eq(account.incomingSeed, K.incoming_seed, 'incoming_seed'); eq(account.outgoingSeed, K.outgoing_seed, 'outgoing_seed');
  eq(T.deriveDsk(account.incomingSeed), K.dsk, 'dsk'); eq(T.deriveViewRoot(account.incomingSeed), K.view_root, 'view_root'); eq(T.deriveDetectRoot(account.incomingSeed), K.detect_root, 'detect_root'); checks += 7;

  // addresses (everything but auth_root, which is checked below).
  const addressRoots = [];
  for (const a of V.addresses) {
    const dJ = T.deriveDiversifier(account.incomingSeed, a.j);
    eq(dJ, a.d_j, `d_${a.j}`);
    const nkSpend = T.deriveNkSpend(account.nk, dJ);
    eq(nkSpend, a.nk_spend, `nk_spend_${a.j}`);
    const nkTag = T.deriveNkTag(nkSpend);
    eq(nkTag, a.nk_tag, `nk_tag_${a.j}`);
    const askJ = T.deriveAsk(account.askBase, a.j);
    const pubSeed = T.deriveAuthPubSeed(askJ);
    eq(pubSeed, a.auth_pub_seed, `auth_pub_seed_${a.j}`);
    eq(T.ownerTag(bytes(a.auth_root), pubSeed, nkTag), a.owner_tag, `owner_tag_${a.j}`);
    addressRoots.push({ j: a.j, askJ, pubSeed, expected: a.auth_root });
    checks += 5;
  }

  // mlkem_seeds
  for (const s of V.mlkem_seeds) { eq(T.kemSeedFromRoot(s.kind, bytes(s.root), s.j), s.seed, `${s.kind} seed j=${s.j}`); tick(); }

  // mlkem_keygen
  const dkV0 = {};
  for (const k of V.mlkem_keygen) {
    eq(T.kemViewSeed(account.incomingSeed, k.j), k.view_seed, `view seed j=${k.j}`);
    eq(T.kemDetectSeed(account.incomingSeed, k.j), k.detect_seed, `detect seed j=${k.j}`);
    const view = T.kemKeygen(bytes(k.view_seed));
    const detect = T.kemKeygen(bytes(k.detect_seed));
    eq(view.ek, k.ek_v, `ek_v j=${k.j}`); eq(detect.ek, k.ek_d, `ek_d j=${k.j}`);
    if (k.j === 0) { dkV0.view = view; dkV0.detect = detect; }
    checks += 4;
  }

  // mlkem_encaps_derand: encapsulate with fixed coins, and decapsulate with the j=0 viewing key.
  for (const c of V.mlkem_encaps_derand) {
    const { ct, ss } = T.kemEncapsulate(bytes(c.ek), bytes(c.coins));
    eq(ct, c.ct, `encaps ct case ${c.case}`); eq(ss, c.ss, `encaps ss case ${c.case}`);
    eq(T.kemDecapsulate(bytes(c.ct), dkV0.view.dk), c.ss, `decaps case ${c.case}`);
    checks += 3;
  }

  // chacha20: the note AEAD with the derived nonce.
  for (const c of V.chacha20) {
    const key = T.noteAeadKey(bytes(c.ss_v));
    const plaintext = T.hexToBytes(hex(felt(BigInt(c.v)).slice(0, 8)) + c.rseed + c.memo);
    const nonce = T.noteAeadNonce(key, plaintext);
    eq(nonce, c.nonce, `chacha nonce case ${c.case}`);
    // Encrypting the same way must reproduce the vector; the module's encryptNote is checked end to end below.
    const { chacha20poly1305 } = await loadChacha();
    eq(chacha20poly1305(key, nonce).encrypt(plaintext), c.encrypted_data, `chacha ciphertext case ${c.case}`);
    checks += 2;
  }

  // detection_tags
  for (const d of V.detection_tags) { assert.equal(T.detectionTag(bytes(d.ss_d)), d.tag, `detection tag case ${d.case}`); tick(); }

  // memo_ct_hash
  const M = V.memo_ct_hash;
  eq(T.memoCtHash({ ctD: bytes(M.ct_d), tag: M.tag, ctV: bytes(M.ct_v), nonce: bytes(M.nonce), encryptedData: bytes(M.encrypted_data), outgoingCt: bytes(M.outgoing_ct) }), M.memo_ct_hash, 'memo_ct_hash'); tick();

  // cross_impl_encrypt: the whole encryption path with fixed coins, then our own decryption of it.
  const X = V.cross_impl_encrypt;
  assert.equal(X.master_sk, K.master_sk, 'cross-impl uses the same master_sk');
  eq(T.kemViewSeed(account.incomingSeed, 0), X.view_seed, 'cross view_seed');
  eq(T.kemDetectSeed(account.incomingSeed, 0), X.detect_seed, 'cross detect_seed');
  const enc = T.encryptNote(BigInt(X.v), bytes(X.rseed), T.hexToBytes(X.memo), bytes(X.ek_v), bytes(X.ek_d), { v: bytes(X.coins_v), d: bytes(X.coins_d) });
  eq(enc.ctV, X.ct_v, 'cross ct_v'); eq(enc.ctD, X.ct_d, 'cross ct_d'); eq(enc.nonce, X.nonce, 'cross nonce'); eq(enc.encryptedData, X.encrypted_data, 'cross encrypted_data');
  assert.equal(enc.tag, X.tag, 'cross tag');
  enc.outgoingCt = bytes(X.outgoing_ct);
  eq(T.memoCtHash(enc), X.memo_ct_hash, 'cross memo_ct_hash');
  const opened = T.decryptMemo(enc, dkV0.view.dk);
  assert.ok(opened, 'our viewing key opens the cross-impl note');
  assert.equal(opened.v, BigInt(X.v), 'decrypted v'); eq(opened.rseed, X.rseed, 'decrypted rseed'); eq(opened.memo, X.memo, 'decrypted memo');
  assert.equal(T.memoText(opened.memo), 'cross-impl test', 'memo text');
  assert.ok(T.detect(enc, dkV0.detect.dk), 'our detection key flags the cross-impl note');
  assert.equal(T.decryptMemo(enc, dkV0.detect.dk), null, 'the wrong key does not open it');
  checks += 14;

  // wots: per-key seed, leaf, signature, and recovery of the leaf from the signature.
  for (const w of V.wots) {
    const askJ = bytes(w.ask_j);
    const pubSeed = T.deriveAuthPubSeed(askJ);
    eq(pubSeed, w.auth_pub_seed, 'wots auth_pub_seed');
    eq(T.authKeySeed(askJ, w.key_idx), w.seed, 'wots key seed');
    eq(T.authLeaf(askJ, pubSeed, w.key_idx), w.leaf, 'wots leaf');
    const sighash = bytes(w.sighash);
    eq(sighash, hex(H('test-sighash')), 'wots sighash input');
    const sig = T.wotsSign(askJ, pubSeed, w.key_idx, sighash);
    assert.equal(sig.map(hex).join(','), w.signature.join(','), 'wots signature');
    eq(T.wotsPkToLeaf(pubSeed, w.key_idx, T.recoverWotsPk(sighash, pubSeed, w.key_idx, sig)), w.leaf, 'leaf recovered from signature');
    const tampered = sig.slice(); tampered[7] = T.hash(tampered[7]);
    assert.notEqual(hex(T.wotsPkToLeaf(pubSeed, w.key_idx, T.recoverWotsPk(sighash, pubSeed, w.key_idx, tampered))), w.leaf, 'a tampered signature recovers another leaf');
    checks += 7;
  }

  // merkle
  for (const [i, m] of V.merkle.entries()) {
    const leaves = m.leaves.map(bytes);
    eq(T.merkleRoot(leaves, m.depth), m.root, `merkle root #${i}`); tick();
    // Each leaf's path must fold back to the root.
    for (let index = 0; index < leaves.length; index++) {
      const path = T.merklePath(leaves, m.depth, index);
      let node = leaves[index];
      for (let d = 0; d < m.depth; d++) node = (index >> d) & 1 ? T.hashMerkle(path[d], node) : T.hashMerkle(node, path[d]);
      eq(node, m.root, `merkle path #${i} leaf ${index}`); tick();
    }
  }

  // notes: commitment and nullifier.
  for (const [i, n] of V.notes.entries()) {
    const rcm = T.deriveRcm(bytes(n.rseed));
    eq(rcm, n.rcm, `rcm #${i}`);
    const otag = T.ownerTag(bytes(n.auth_root), bytes(n.auth_pub_seed), bytes(n.nk_tag));
    eq(otag, n.owner_tag, `owner_tag #${i}`);
    const cm = T.commit(bytes(n.d_j), BigInt(n.v), rcm, otag);
    eq(cm, n.cm, `cm #${i}`);
    eq(T.nullifier(bytes(n.nk_spend), cm, n.pos), n.nf, `nf #${i}`);
    const address = { dJ: bytes(n.d_j), authRoot: bytes(n.auth_root), pubSeed: bytes(n.auth_pub_seed), nkTag: bytes(n.nk_tag) };
    assert.ok(T.acceptsNote(address, cm, { v: BigInt(n.v), rseed: bytes(n.rseed) }), `note #${i} accepted`);
    assert.ok(!T.acceptsNote(address, cm, { v: BigInt(n.v) + 1n, rseed: bytes(n.rseed) }), `note #${i} with another value refused`);
    checks += 6;
  }

  // sighash
  for (const [i, s] of V.sighash.entries()) { eq(T.fold(s.items.map(bytes)), s.result, `sighash #${i}`); tick(); }
  eq(V.sighash[1].items[1], hex(H('domain')), 'sighash vector domain item'); tick();

  // account_ids
  for (const a of V.account_ids) { eq(T.accountId(a.string), a.id, `account id ${JSON.stringify(a.string)}`); tick(); }

  // wire_encoding
  const W = V.wire_encoding;
  const fill = (n, f) => Uint8Array.from({ length: n }, (_, i) => f(i));
  const wireNote = { ctD: fill(1088, (i) => i % 256), tag: 42, ctV: fill(1088, (i) => (i + 50) % 256), nonce: fill(12, () => 0xaa), encryptedData: fill(1080, (i) => (i + 100) % 256), outgoingCt: fill(185, () => 0xbb) };
  eq(T.encodeEncryptedNote(wireNote), W.encrypted_note, 'encrypted_note encoding');
  const decoded = T.decodeEncryptedNote(bytes(W.encrypted_note));
  eq(T.encodeEncryptedNote(decoded), W.encrypted_note, 'encrypted_note round trip');
  assert.equal(decoded.tag, 42, 'decoded tag');
  const wireCm = H('wire-test-cm');
  eq(T.encodePublishedNote(wireCm, wireNote), W.published_note, 'published_note encoding');
  const published = T.decodePublishedNote(bytes(W.published_note));
  eq(published.cm, hex(wireCm), 'published_note cm');
  eq(T.encodeNoteMemo(42, wireCm, wireNote), W.note_memo, 'note_memo encoding');
  const memo = T.decodeNoteMemo(bytes(W.note_memo));
  assert.equal(memo.index, 42n, 'note_memo index'); eq(memo.cm, hex(wireCm), 'note_memo cm'); eq(T.encodeEncryptedNote(memo.enc), W.encrypted_note, 'note_memo enc');
  const a0 = V.addresses[0];
  const address0 = { dJ: bytes(a0.d_j), authRoot: bytes(a0.auth_root), pubSeed: bytes(a0.auth_pub_seed), nkTag: bytes(a0.nk_tag), ekV: dkV0.view.ek, ekD: dkV0.detect.ek };
  eq(T.encodePaymentAddress(address0), W.payment_address, 'payment_address encoding');
  const back = T.decodePaymentAddress(bytes(W.payment_address));
  eq(T.encodePaymentAddress(T.paymentAddressFromJSON(T.paymentAddressToJSON(back))), W.payment_address, 'payment_address JSON round trip');
  assert.throws(() => T.decodeEncryptedNote(bytes(W.encrypted_note).slice(1)), /3455 bytes/, 'short note refused');
  checks += 12;

  // Deposit pool identifiers: the spec's recipient string shape.
  const pk = T.depositPubkeyHash(H('domain'), address0.authRoot, address0.pubSeed, felt(7));
  assert.match(T.depositRecipient(pk), /^deposit:[0-9a-f]{64}$/, 'deposit recipient shape');
  assert.equal(T.depositBalanceKey(pk), `/tzel/v1/state/deposits/balance/${hex(pk)}`, 'deposit balance key'); checks += 2;

  // Full auth roots: 65536 leaves each, minutes of hashing, so only with TZEL_FULL=1; the
  // default run times 512 leaves and reports what a full tree would take.
  if (!process.env.TZEL_FULL) {
    const r = addressRoots[0];
    const started = Date.now();
    for (let i = 0; i < 512; i++) T.authLeaf(r.askJ, r.pubSeed, i);
    const perLeaf = (Date.now() - started) / 512;
    console.log(`tzel vectors: ${perLeaf.toFixed(2)} ms per auth leaf, about ${(perLeaf * T.AUTH_TREE_SIZE / 1000).toFixed(0)} s per address (auth roots skipped; TZEL_FULL=1 checks them)`);
  }
  const roots = process.env.TZEL_FULL ? addressRoots : [];
  for (const r of roots) {
    const started = Date.now();
    const levels = T.buildAuthTree(r.askJ, r.pubSeed);
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    eq(T.authRootOf(levels), r.expected, `auth_root_${r.j}`); tick();
    // A leaf's path folds to the root with the XMSS tree-node hash.
    for (const index of [0, 1, 65535, 12345]) {
      const path = T.authPath(levels, index);
      let node = levels[0][index];
      for (let level = 0; level < T.AUTH_DEPTH; level++) {
        const nodeIdx = index >> (level + 1);
        node = (index >> level) & 1 ? T.xmssTreeNode(r.pubSeed, level, nodeIdx, path[level], node) : T.xmssTreeNode(r.pubSeed, level, nodeIdx, node, path[level]);
      }
      eq(node, r.expected, `auth path j=${r.j} index ${index}`); tick();
    }
    console.log(`tzel vectors: auth tree j=${r.j} built in ${seconds} s`);
  }

  console.log(`tzel vectors: ${checks} checks passed against ${path.relative(process.cwd(), vectorsPath)}`);
})().catch((error) => { console.error(error); process.exit(1); });

async function loadChacha() {
  const result = await build({ stdin: { contents: 'export { chacha20poly1305 } from "@noble/ciphers/chacha.js";', resolveDir: path.resolve(__dirname, '../src') }, bundle: true, write: false, format: 'iife', globalName: 'C', platform: 'browser', target: 'safari17' });
  const context = { TextEncoder, TextDecoder, crypto: crypto.webcrypto };
  vm.createContext(context); vm.runInContext(result.outputFiles[0].text, context); return context.C;
}
