// Offline checks of the transfer (Send shielded) path: the kernel inbox wire against the
// reference crate's bytes for a sample three-input message (length and SHA-256 only), the
// payment-address fingerprint, the sighash, the witness layout, the three notes (the
// recipient's found by the recipient's wallet with its memo, the change by ours) and refusals.
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

const REFERENCE_TRANSFER_WIRE = { length: 10711, sha256: '6a145ce6ccd0b304eb7de702149f205164718cebc13fbde5b83d78e0cd25347e' };

(async () => {
  const T = await load('tzel.js');
  const S = await load('shield.js');
  const hex = T.bytesToHex, bytes = T.hexToBytes;
  const fill = (n, f) => bytes(Buffer.from(Uint8Array.from({ length: n }, (_, i) => f(i) & 0xff)).toString('hex'));
  const feltOfHex = (h) => bytes(BigInt(h).toString(16).padStart(64, '0').match(/../g).reverse().join(''));
  let checks = 0;
  const tick = () => { checks++; };

  // ── Kernel wire: the reference's sample transfer message, byte for byte.
  const sampleNote = (v) => ({ ctD: fill(1088, () => v), tag: 17, ctV: fill(1088, () => v ^ 0x5a), nonce: fill(12, () => (v + 2) & 0xff), encryptedData: fill(1080, () => (v + 1) & 0xff), outgoingCt: fill(185, () => (v + 3) & 0xff) });
  const wire = T.encodeTransferMessage({
    root: fill(32, () => 0x11), nullifiers: [0x21, 0x22, 0x23].map((v) => fill(32, () => v)), fee: 100000n,
    cms: [0x31, 0x32, 0x33].map((v) => fill(32, () => v)), encs: [0x61, 0x62, 0x63].map(sampleNote),
    proofBytes: bytes('aabbcc'), outputPreimage: [fill(32, () => 7), fill(32, () => 8)],
  });
  assert.equal(wire.length, REFERENCE_TRANSFER_WIRE.length); assert.equal(crypto.createHash('sha256').update(wire).digest('hex'), REFERENCE_TRANSFER_WIRE.sha256, 'the reference bytes'); checks += 2;
  assert.equal(hex(wire.slice(0, 7)), '110003000029d0', 'version 17, transfer tag 3, body length'); tick();

  // ── Two wallets: ours (two notes at address 0, keys 5 and 6 real) and the recipient's.
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
  const bobAccount = await S.tzelAccount(hex(T.feltOfInt(31337)));
  const bobKeys = await S.tzelAddressKeys(bobAccount, 0);
  const bobRecord = { index: 0, dJ: bobKeys.dJ, authRoot: hex(T.feltOfInt(2)), pubSeed: bobKeys.pubSeed, nkTag: bobKeys.nkTag, ekV: bobKeys.ekV, ekD: bobKeys.ekD };
  const bob = { d_j: bobKeys.dJ, auth_root: hex(T.feltOfInt(2)), auth_pub_seed: bobKeys.pubSeed, nk_tag: bobKeys.nkTag, ek_v: bobKeys.ekV, ek_d: bobKeys.ekD };
  const producerAccount = await S.tzelAccount(hex(T.feltOfInt(4242)));
  const producerKeys = await S.tzelAddressKeys(producerAccount, 0);
  const producerAddress = { d_j: producerKeys.dJ, auth_root: hex(T.feltOfInt(1)), auth_pub_seed: producerKeys.pubSeed, nk_tag: producerKeys.nkTag, ek_v: producerKeys.ekV, ek_d: producerKeys.ekD };
  const authDomain = hex(T.feltOfInt(99));

  // ── The recipient is the payment address itself; its fingerprint is the hash of the canonical record.
  const parsed = await S.tzelPaymentAddress(bob);
  assert.deepEqual({ ...parsed.address }, bob); tick();
  assert.equal(parsed.fingerprint, hex(T.hash(T.encodePaymentAddress(T.paymentAddressFromJSON(bob))))); tick();
  assert.equal((await S.tzelPaymentAddress(JSON.stringify({ index: 3, address: bob }))).fingerprint, parsed.fingerprint, 'the reference CLI wrapper'); tick();
  assert.equal((await S.tzelPaymentAddress(bobRecord)).fingerprint, parsed.fingerprint, 'our own record form'); tick();
  assert.notEqual((await S.tzelPaymentAddress(producerAddress)).fingerprint, parsed.fingerprint); tick();
  await assert.rejects(() => S.tzelPaymentAddress({ ...bob, ek_v: 'aa' }), /1184 bytes/); tick();
  await assert.rejects(() => S.tzelPaymentAddress('[]'), /JSON object/); tick();

  const inputs = [
    { note: { index: 1, cm: hex(noteA.cm), rseed: hex(noteA.rseed), v: '1500000' }, address, keyIdx: 5, authPath: authPath(5) },
    { note: { index: 3, cm: hex(noteB.cm), rseed: hex(noteB.rseed), v: '1000000' }, address, keyIdx: 6, authPath: authPath(6) },
  ];
  const request = { account, authDomain, root, leafCms, amount: '2000000', fee: '100000', producerFee: '100000', recipient: bob, memo: 'for lunch', inputs, changeAddress, producerAddress };
  const built = await S.tzelBuildTransfer(request);
  const n = 2, per = 9 + 48 + 16 + 133;
  assert.equal(built.witness.length, 1 + 4 + n * per + 24); assert.equal(built.witness[0], '0x' + (4 + n * per + 24).toString(16)); assert.equal(built.witness[1], '0x2'); checks += 3;
  assert.equal(built.witness[4], '0x186a0'); assert.equal(built.changeMutez, '300000'); assert.equal(built.recipientFingerprint, parsed.fingerprint); checks += 3;
  const nkSpend = T.deriveNkSpend(bytes(account.nk), bytes(keys.dJ));
  assert.deepEqual([...built.nullifiers], [hex(T.nullifier(nkSpend, noteA.cm, 1)), hex(T.nullifier(nkSpend, noteB.cm, 3))]); tick();
  assert.deepEqual([...built.publicOutputs], [authDomain, root, ...built.nullifiers, hex(T.feltOfInt(100000)), ...built.cms, ...built.mhs]); tick();
  // The three outputs sit at the tail as cm, d_j, v, rseed, auth_root, auth_pub_seed, nk_tag, mh.
  const tail = 1 + 4 + n * per;
  assert.equal(built.witness[tail], T.feltHex(bytes(built.cms[0]))); assert.equal(built.witness[tail + 1], T.feltHex(bytes(bob.d_j))); assert.equal(built.witness[tail + 2], '0x1e8480'); checks += 3;
  assert.equal(built.witness[tail + 8], T.feltHex(bytes(built.cms[1]))); assert.equal(built.witness[tail + 10], '0x493e0', 'change value'); assert.equal(built.witness[tail + 16], T.feltHex(bytes(built.cms[2]))); checks += 3;
  assert.equal(built.witness[tail + 23], T.feltHex(bytes(built.mhs[2]))); tick();
  // The sighash and the signatures.
  const sighash = T.transferSighash({ authDomain: bytes(authDomain), root: bytes(root), nullifiers: built.nullifiers.map(bytes), fee: 100000n, outputs: built.cms.map((cm, i) => ({ cm: bytes(cm), mh: bytes(built.mhs[i]) })) });
  assert.equal(built.sighash, hex(sighash)); tick();
  const sigStart = 1 + 4 + 9 * n + 48 * n + 16 * n;
  for (const [i, k] of [[0, 5], [1, 6]]) {
    const sig = built.witness.slice(sigStart + 133 * i, sigStart + 133 * (i + 1)).map(feltOfHex);
    assert.equal(hex(T.wotsPkToLeaf(pubSeed, k, T.recoverWotsPk(sighash, pubSeed, k, sig))), hex(leaves[k]), `signature ${i} recovers leaf ${k}`); tick();
  }
  // Bob's wallet finds the recipient note with the memo; ours finds the change under address 1; neither sees the other's.
  const published = [{ index: 4, bytes: built.cms[0] + built.encs[0] }, { index: 5, bytes: built.cms[1] + built.encs[1] }, { index: 6, bytes: built.cms[2] + built.encs[2] }];
  const bobScan = await S.tzelScan(bobAccount, [bobRecord], published);
  assert.equal(bobScan.length, 1); assert.equal(bobScan[0].index, 4); assert.equal(bobScan[0].v, '2000000'); assert.equal(bobScan[0].memo, 'for lunch'); assert.equal(bobScan[0].rseed, built.recipientRseed); checks += 5;
  const ourScan = await S.tzelScan(account, [address, changeAddress], published);
  assert.equal(ourScan.length, 1); assert.equal(ourScan[0].index, 5); assert.equal(ourScan[0].v, '300000'); assert.equal(ourScan[0].addressIndex, 1); checks += 4;
  const recovered = T.decryptOutgoingRecovery(bytes(account.outgoingSeed), bytes(built.cms[0]), T.decodeEncryptedNote(bytes(built.encs[0])).outgoingCt);
  assert.equal(recovered.role, 'transfer_recipient'); assert.equal(recovered.v, 2000000n); assert.equal(hex(recovered.dJ), bob.d_j, 'the sender can recover whom it paid'); checks += 3;
  assert.equal(T.decryptOutgoingRecovery(bytes(account.outgoingSeed), bytes(built.cms[1]), T.decodeEncryptedNote(bytes(built.encs[1])).outgoingCt).role, 'transfer_change'); tick();

  // ── An exact transfer still makes three notes, the change one for zero.
  const exact = await S.tzelBuildTransfer({ ...request, amount: '2300000' });
  assert.equal(exact.changeMutez, '0'); assert.equal(exact.cms.length, 3); assert.equal(exact.witness[tail + 10], '0x0'); checks += 3;

  // ── Refusals.
  await assert.rejects(() => S.tzelBuildTransfer({ ...request, amount: '2400000' }), /less than/); tick();
  await assert.rejects(() => S.tzelBuildTransfer({ ...request, amount: '0' }), /0 tez/); tick();
  await assert.rejects(() => S.tzelBuildTransfer({ ...request, changeAddress: null }), /change needs an address/); tick();
  await assert.rejects(() => S.tzelBuildTransfer({ ...request, memo: 'x'.repeat(1025) }), /memo/); tick();
  await assert.rejects(() => S.tzelBuildTransfer({ ...request, recipient: { ...bob, nk_tag: 'zz' } }), /nk_tag|hex/); tick();
  await assert.rejects(() => S.tzelBuildTransfer({ ...request, root: hex(T.feltOfInt(5)) }), /rollup's root/); tick();
  await assert.rejects(() => S.tzelBuildTransfer({ ...request, inputs: [inputs[0], { ...inputs[1], keyIdx: 5, authPath: authPath(5) }] }), /sign twice/); tick();

  // ── The message for the operator.
  const fields = { root, nullifiers: built.nullifiers, fee: '100000', cms: built.cms, encs: built.encs, proofBytes: 'aabbcc', expectedOutputs: built.publicOutputs };
  const message = await S.tzelEncodeTransferMessage({ ...fields, outputPreimage: built.publicOutputs });
  const outputs = 2 + n + 7;
  assert.equal(message.length / 2, 7 + 32 + (4 + 36 * n) + 8 + 96 + (4 + 4 + 3 + 4 + 32 * outputs) + 3 * (4 + 3455)); tick();
  assert.equal(message.slice(0, 6), '110003'); tick();
  const programHash = '655b8fa9096b9d23aa8f3f722c80f776b6322831320206cbba6a1e84b00ffb00';
  const wrapped = await S.tzelEncodeTransferMessage({ ...fields, programHash, outputPreimage: [hex(T.feltOfInt(1)), hex(T.feltOfInt(outputs + 3)), programHash, hex(T.feltOfInt(outputs)), ...built.publicOutputs] });
  assert.equal(wrapped.length, message.length + 2 * 4 * 32); tick();
  await assert.rejects(() => S.tzelEncodeTransferMessage({ ...fields, outputPreimage: exact.publicOutputs }), /public outputs/); tick();

  console.log(`tzel transfer: ${checks} checks passed`);
})().catch((e) => { console.error(e); process.exit(1); });
