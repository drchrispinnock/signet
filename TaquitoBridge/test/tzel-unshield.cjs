// Offline checks of the unshield path in src/tzel.js and src/shield.js: the kernel inbox wire
// against the reference crate's bytes for two sample messages (with and without a change note;
// only their lengths and SHA-256s are kept here), the sighash, the Cairo witness layout, the
// per-input signatures and Merkle paths, the change and producer notes, the refusals, and the
// outbox-execution parameters.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { build } = require('esbuild');

async function load(file) {
  const source = fs.readFileSync(path.resolve(__dirname, '../src', file), 'utf8');
  const result = await build({ stdin: { contents: source, resolveDir: path.resolve(__dirname, '../src'), sourcefile: file }, bundle: true, write: false, format: 'iife', globalName: 'API', platform: 'browser', target: 'safari17', external: ['@taquito/taquito', './signers.js', './operations.js'] });
  const context = { console, TextEncoder, TextDecoder, crypto: crypto.webcrypto, require: () => ({}) };
  vm.createContext(context); vm.runInContext(result.outputFiles[0].text, context); return context.API;
}

const REFERENCE_WITH_CHANGE = { length: 7233, sha256: '2de820d503de8f1aec0e11864f93bf4e1a9227eb0f48726be8957e241302e1c6' };
const REFERENCE_WITHOUT_CHANGE = { length: 3774, sha256: '02fa98b8f6ba6b70050f8214091c5f4e63940612164d0404f4c49104969afabb' };
const RECIPIENT = 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb';

(async () => {
  const T = await load('tzel.js');
  const S = await load('shield.js');
  const hex = T.bytesToHex, bytes = T.hexToBytes;
  const fill = (n, f) => bytes(Buffer.from(Uint8Array.from({ length: n }, (_, i) => f(i) & 0xff)).toString('hex'));
  const feltOfHex = (h) => bytes(BigInt(h).toString(16).padStart(64, '0').match(/../g).reverse().join(''));
  const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
  let checks = 0;
  const tick = () => { checks++; };

  // ── Kernel wire: the reference's two sample unshield messages, byte for byte.
  const sampleNote = (v) => ({ ctD: fill(1088, () => v), tag: 17, ctV: fill(1088, () => v ^ 0x5a), nonce: fill(12, () => (v + 2) & 0xff), encryptedData: fill(1080, () => (v + 1) & 0xff), outgoingCt: fill(185, () => (v + 3) & 0xff) });
  const sample = {
    root: fill(32, () => 0x11), nullifiers: [fill(32, () => 0x21), fill(32, () => 0x22)], vPub: 1234567n, fee: 100000n, recipient: RECIPIENT,
    cmChange: fill(32, () => 0x33), proofBytes: bytes('aabbcc'), outputPreimage: [fill(32, () => 7), fill(32, () => 8)], cmFee: fill(32, () => 0x44), producerEnc: sampleNote(0x77),
  };
  const withChange = T.encodeUnshieldMessage({ ...sample, changeEnc: sampleNote(0x66) });
  assert.equal(withChange.length, REFERENCE_WITH_CHANGE.length); assert.equal(sha(withChange), REFERENCE_WITH_CHANGE.sha256, 'with change: the reference bytes'); checks += 2;
  const withoutChange = T.encodeUnshieldMessage({ ...sample, changeEnc: null });
  assert.equal(withoutChange.length, REFERENCE_WITHOUT_CHANGE.length); assert.equal(sha(withoutChange), REFERENCE_WITHOUT_CHANGE.sha256, 'without change: the reference bytes'); checks += 2;
  assert.equal(hex(withChange.slice(0, 7)), '11000400001c3a', 'version 17, unshield tag 4, body length'); tick();
  assert.equal(hex(withChange.slice(39, 47)), '0000004800000020', 'nullifier list: 36 bytes per felt, each length-prefixed'); tick();
  assert.equal(hex(withChange.slice(115, 131)), '87d6120000000000a086010000000000', 'v_pub and fee as u64le'); tick();
  assert.equal(hex(withChange.slice(131, 135)), '00000024', 'recipient length'); tick();
  assert.equal(withoutChange[7 + 32 + 76 + 16 + 40 + 32 + 79], 0x00, 'no change note: a 0x00 option byte'); tick();
  assert.equal(withChange[7 + 32 + 76 + 16 + 40 + 32 + 79], 0xff, 'a change note: 0xff then the length-prefixed note'); tick();

  // ── A wallet with two notes at address 0 (real leaves for keys 5 and 6) and a change address 1.
  const masterSk = hex(T.feltOfInt(777));
  const account = await S.tzelAccount(masterSk);
  const keys = await S.tzelAddressKeys(account, 0);
  const askJ = bytes(keys.askJ), pubSeed = bytes(keys.pubSeed);
  const leaves = Array.from({ length: T.AUTH_TREE_SIZE }, () => T.randomFelt());
  for (const k of [5, 6]) leaves[k] = T.authLeaf(askJ, pubSeed, k);
  const levels = T.authTreeLevels(pubSeed, leaves);
  const authRoot = hex(T.authRootOf(levels));
  const authPath = (k) => T.authPath(levels, k).map(hex);
  const address = { index: 0, dJ: keys.dJ, authRoot, pubSeed: keys.pubSeed, nkTag: keys.nkTag, ekV: keys.ekV, ekD: keys.ekD };
  const addressBytes = { ...address, dJ: bytes(keys.dJ), authRoot: bytes(authRoot), pubSeed, nkTag: bytes(keys.nkTag), ekV: bytes(keys.ekV), ekD: bytes(keys.ekD) };
  const noteA = T.buildOutputNote(addressBytes, 1500000n, '', null);
  const noteB = T.buildOutputNote(addressBytes, 1000000n, '', null);
  const leafCms = [T.randomFelt(), noteA.cm, T.randomFelt(), noteB.cm].map(hex);
  const root = hex(T.merkleRoot(leafCms.map(bytes), T.TREE_DEPTH));
  const changeKeys = await S.tzelAddressKeys(account, 1);
  const changeAddress = { index: 1, dJ: changeKeys.dJ, authRoot: hex(T.feltOfInt(1)), pubSeed: changeKeys.pubSeed, nkTag: changeKeys.nkTag, ekV: changeKeys.ekV, ekD: changeKeys.ekD };
  const producerAccount = await S.tzelAccount(hex(T.feltOfInt(4242)));
  const producerKeys = await S.tzelAddressKeys(producerAccount, 0);
  const producerAddress = { d_j: producerKeys.dJ, auth_root: hex(T.feltOfInt(1)), auth_pub_seed: producerKeys.pubSeed, nk_tag: producerKeys.nkTag, ek_v: producerKeys.ekV, ek_d: producerKeys.ekD };
  const authDomain = hex(T.feltOfInt(99));
  const inputs = [
    { note: { index: 1, cm: hex(noteA.cm), rseed: hex(noteA.rseed), v: '1500000' }, address, keyIdx: 5, authPath: authPath(5) },
    { note: { index: 3, cm: hex(noteB.cm), rseed: hex(noteB.rseed), v: '1000000' }, address, keyIdx: 6, authPath: authPath(6) },
  ];
  const request = { account, authDomain, root, leafCms, vPub: '2000000', fee: '100000', producerFee: '100000', recipient: RECIPIENT, inputs, changeAddress, producerAddress };
  const built = await S.tzelBuildUnshield(request);
  const n = 2, per = 9 + 48 + 16 + 133;
  assert.equal(built.witness.length, 1 + 6 + n * per + 15); assert.equal(built.witness[0], '0x' + (6 + n * per + 15).toString(16)); assert.equal(built.witness[1], '0x2'); checks += 3;
  assert.equal(built.witness[4], '0x1e8480'); assert.equal(built.witness[5], '0x186a0'); assert.equal(built.witness[6], T.feltHex(T.accountId(RECIPIENT))); checks += 3;
  assert.equal(built.recipientId, hex(T.accountId(RECIPIENT))); tick();
  assert.equal(built.changeMutez, '300000'); assert.ok(built.changeCm && built.changeEnc); checks += 2;
  // The nullifiers are the notes' under address 0's spending key, in input order, and the public outputs are the kernel's 2 + n + 7.
  const nkSpend = T.deriveNkSpend(bytes(account.nk), bytes(keys.dJ));
  assert.deepEqual([...built.nullifiers], [hex(T.nullifier(nkSpend, noteA.cm, 1)), hex(T.nullifier(nkSpend, noteB.cm, 3))]); tick();
  assert.deepEqual([...built.publicOutputs], [authDomain, root, ...built.nullifiers, hex(T.feltOfInt(2000000)), hex(T.feltOfInt(100000)), built.recipientId, built.changeCm, built.changeMh, built.producerCm, built.producerMh]); tick();
  assert.equal(built.witness[7], T.feltHex(bytes(built.nullifiers[0]))); assert.equal(built.witness[7 + 9], T.feltHex(bytes(built.nullifiers[1]))); assert.equal(built.witness[7 + 4], '0x5'); assert.equal(built.witness[7 + 9 + 4], '0x6'); checks += 4;
  assert.equal(built.witness[7 + 8], '0x1'); assert.equal(built.witness[7 + 9 + 8], '0x3', 'tree positions'); checks += 2;
  // The sighash is the fold the spec names; each input's signature recovers its leaf.
  const sighash = T.unshieldSighash({ authDomain: bytes(authDomain), root: bytes(root), nullifiers: built.nullifiers.map(bytes), vPub: 2000000n, fee: 100000n, recipientId: bytes(built.recipientId), cmChange: bytes(built.changeCm), mhChange: bytes(built.changeMh), cmFee: bytes(built.producerCm), mhFee: bytes(built.producerMh) });
  assert.equal(built.sighash, hex(sighash)); tick();
  const sigStart = 1 + 6 + 9 * n + 48 * n + 16 * n;
  for (const [i, k] of [[0, 5], [1, 6]]) {
    const sig = built.witness.slice(sigStart + 133 * i, sigStart + 133 * (i + 1)).map(feltOfHex);
    assert.equal(hex(T.wotsPkToLeaf(pubSeed, k, T.recoverWotsPk(sighash, pubSeed, k, sig))), hex(leaves[k]), `signature ${i} recovers leaf ${k}`); tick();
  }
  // Each input's commitment path leads to the root.
  const pathStart = 1 + 6 + 9 * n;
  for (const [i, pos0, cm] of [[0, 1, noteA.cm], [1, 3, noteB.cm]]) {
    const siblings = built.witness.slice(pathStart + 48 * i, pathStart + 48 * (i + 1)).map(feltOfHex);
    let node = cm, pos = pos0;
    for (const sib of siblings) { node = (pos & 1) === 0 ? T.hashMerkle(node, sib) : T.hashMerkle(sib, node); pos >>= 1; }
    assert.equal(hex(node), root, `commitment path ${i}`); tick();
  }
  // The change note is found by the scan under address 1 and carries the outgoing record; the producer's is not ours.
  const scan = await S.tzelScan(account, [address, changeAddress], [{ index: 4, bytes: built.changeCm + built.changeEnc }, { index: 5, bytes: built.producerCm + built.producerEnc }]);
  assert.equal(scan.length, 1); assert.equal(scan[0].index, 4); assert.equal(scan[0].v, '300000'); assert.equal(scan[0].addressIndex, 1); assert.equal(scan[0].rseed, built.changeRseed); checks += 5;
  const recovered = T.decryptOutgoingRecovery(bytes(account.outgoingSeed), bytes(built.changeCm), T.decodeEncryptedNote(bytes(built.changeEnc)).outgoingCt);
  assert.equal(recovered.role, 'unshield_change'); assert.equal(recovered.v, 300000n); checks += 2;
  assert.equal(await S.tzelNoteCommitment(changeAddress.dJ, '300000', built.changeRseed, changeAddress.authRoot, changeAddress.pubSeed, changeAddress.nkTag), built.changeCm, 'the change commitment recomputes'); tick();
  assert.equal(await S.tzelMerkleRoot(leafCms), root); tick();

  // ── No change: the flag and the seven change fields are zero, cm_change and mh_change are zero outputs.
  const exact = await S.tzelBuildUnshield({ ...request, vPub: '2300000', changeAddress: null });
  assert.equal(exact.changeMutez, '0'); assert.equal(exact.changeCm, null); checks += 2;
  const flag = 1 + 6 + n * per;
  assert.deepEqual([...exact.witness.slice(flag, flag + 8)], Array(8).fill('0x0')); tick();
  assert.equal(exact.publicOutputs[2 + n + 3], hex(T.feltOfInt(0))); assert.equal(exact.publicOutputs[2 + n + 4], hex(T.feltOfInt(0))); checks += 2;

  // ── Refusals, before anything is signed.
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, root: hex(T.feltOfInt(5)) }), /rollup's root/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, vPub: '2400000' }), /less than/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, recipient: 'bob' }), /recipient/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, changeAddress: null }), /change needs an address/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, inputs: [inputs[0], { ...inputs[1], keyIdx: 5, authPath: authPath(5) }] }), /sign twice/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, inputs: [inputs[0], { ...inputs[1], authPath: authPath(5) }] }), /auth path/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, inputs: [{ ...inputs[0], note: { ...inputs[0].note, index: 2 } }] }), /not the commitment at/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, inputs: [{ ...inputs[0], note: { ...inputs[0].note, v: '1500001' } }] }), /not the commitment at|not a note of/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, inputs: Array(8).fill(inputs[0]) }), /one to seven/); tick();
  await assert.rejects(() => S.tzelBuildUnshield({ ...request, account: producerAccount }), /signing seed/); tick();

  // ── The message for the operator, from a (fake) proof bundle, plain and bootloader-wrapped outputs.
  const messageFields = { root, nullifiers: built.nullifiers, vPub: '2000000', fee: '100000', recipient: RECIPIENT, cmChange: built.changeCm, changeEnc: built.changeEnc, cmFee: built.producerCm, producerEnc: built.producerEnc, proofBytes: 'aabbcc', expectedOutputs: built.publicOutputs };
  const message = await S.tzelEncodeUnshieldMessage({ ...messageFields, outputPreimage: built.publicOutputs });
  const outputs = 2 + n + 7;
  assert.equal(message.length / 2, 7 + 32 + (4 + 36 * n) + 16 + (4 + 36) + 32 + (4 + 4 + 3 + 4 + 32 * outputs) + (1 + 4 + 3455) + 32 + (4 + 3455)); tick();
  assert.equal(message.slice(0, 6), '110004'); assert.equal(message.slice(14, 78), root); checks += 2;
  const programHash = '655b8fa9096b9d23aa8f3f722c80f776b6322831320206cbba6a1e84b00ffb00';
  const bootloader = [hex(T.feltOfInt(1)), hex(T.feltOfInt(outputs + 3)), programHash, hex(T.feltOfInt(outputs)), ...built.publicOutputs];
  const wrapped = await S.tzelEncodeUnshieldMessage({ ...messageFields, programHash, outputPreimage: bootloader });
  assert.equal(wrapped.length, message.length + 2 * 4 * 32); tick();
  await assert.rejects(() => S.tzelEncodeUnshieldMessage({ ...messageFields, outputPreimage: built.publicOutputs.slice(0, outputs - 1) }), /public outputs/); tick();
  await assert.rejects(() => S.tzelEncodeUnshieldMessage({ ...messageFields, programHash: 'ab'.repeat(32), outputPreimage: bootloader }), /public outputs/); tick();
  const plain = await S.tzelEncodeUnshieldMessage({ ...messageFields, cmChange: hex(T.feltOfInt(0)), changeEnc: null, outputPreimage: exact.publicOutputs, expectedOutputs: exact.publicOutputs });
  assert.equal(plain.length / 2, message.length / 2 - (4 + 3455)); tick();

  // ── Outbox execution parameters are checked before any node is contacted.
  await assert.rejects(() => S.sendOutboxExecution('http://127.0.0.1:1', '{}', 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb', 'src13Ycd5ZPbQGiLiVuWqAMUhNuaWafb5T7KoqHsMGEAStvScGDFgx', 'aa', '{}'), /Smart Rollup/); tick();
  await assert.rejects(() => S.sendOutboxExecution('http://127.0.0.1:1', '{}', 'sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK', 'src1bad', 'aa', '{}'), /commitment hash/); tick();
  await assert.rejects(() => S.sendOutboxExecution('http://127.0.0.1:1', '{}', 'sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK', 'src13Ycd5ZPbQGiLiVuWqAMUhNuaWafb5T7KoqHsMGEAStvScGDFgx', '', '{}'), /proof is empty/); tick();

  console.log(`tzel unshield: ${checks} checks passed`);
})().catch((e) => { console.error(e); process.exit(1); });
