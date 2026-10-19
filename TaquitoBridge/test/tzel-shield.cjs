// Offline checks of the shield path in src/tzel.js and src/shield.js: the ticketer call, the
// deposit-pool id, the output notes and their outgoing-recovery records, the WOTS+ signature
// over the shield sighash, the Cairo witness layout and the kernel inbox wire encoding.
//
// The wire encoding is compared with the reference implementation's bytes for one sample
// shield message (`kernel_wire.rs`, version 17, built with the reference crate from a fixed
// sample; only its length and SHA-256 are kept here).
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

const REFERENCE_SHIELD_WIRE = { length: 7112, sha256: 'bb341ab4fe1ea2b4e8ea3a14e637364f53486919423f3918c5ea3e77478eb4af' };

(async () => {
  const T = await load('tzel.js');
  const S = await load('shield.js');
  const hex = T.bytesToHex, bytes = T.hexToBytes;
  // Byte arrays are made in the module's realm (bytes of hex): a Node-realm Uint8Array fails its instanceof check.
  const fill = (n, f) => bytes(Buffer.from(Uint8Array.from({ length: n }, (_, i) => f(i) & 0xff)).toString('hex'));
  let checks = 0;
  const tick = () => { checks++; };

  // ── Kernel wire: the reference's sample shield message, byte for byte.
  const sampleNote = (v) => ({ ctD: fill(1088, () => v), tag: 17, ctV: fill(1088, () => v ^ 0x5a), nonce: fill(12, () => (v + 2) & 0xff), encryptedData: fill(1080, () => (v + 1) & 0xff), outgoingCt: fill(185, () => (v + 3) & 0xff) });
  const wire = T.encodeShieldMessage({
    pubkeyHash: fill(32, () => 0x42), fee: 3n, v: 42n, producerFee: 5n,
    proofBytes: bytes('aabbcc'), outputPreimage: [fill(32, () => 7), fill(32, () => 8)],
    clientCm: fill(32, () => 0x55), clientEnc: sampleNote(0x66), producerCm: fill(32, () => 9), producerEnc: sampleNote(0x77),
  });
  assert.equal(wire.length, REFERENCE_SHIELD_WIRE.length, 'wire length'); tick();
  assert.equal(crypto.createHash('sha256').update(wire).digest('hex'), REFERENCE_SHIELD_WIRE.sha256, 'wire bytes match the reference encoding'); tick();
  assert.equal(hex(wire.slice(0, 3)), '110002', 'version 17 little-endian, shield tag 2'); tick();
  assert.equal(hex(wire.slice(35, 59)), '03000000000000002a000000000000000500000000000000', 'fee, v, producer_fee as u64le'); tick();
  assert.equal(hex(wire.slice(59, 70)), '0000004b00000003aabbcc', 'proof wrapper length, then proof length and bytes'); tick();

  // ── The ticketer call.
  const pool = 'ab'.repeat(32);
  const params = await S.shieldDepositParams('KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4', 'sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK', pool, '1500000');
  assert.equal(params.amount, 1500000); assert.equal(params.mutez, true); assert.equal(params.parameter.entrypoint, 'mint');
  assert.equal(params.parameter.value.args[0].bytes, hex(new TextEncoder().encode('deposit:' + pool)), 'receiver is the ASCII of deposit:<hex>');
  assert.equal(params.parameter.value.args[1].string, 'sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK'); checks += 4;
  await assert.rejects(() => S.shieldDepositParams('KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4', 'sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK', pool, '0'), /0 tez/); tick();
  await assert.rejects(() => S.shieldDepositParams('tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb', 'sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK', pool, '1'), /ticketer/); tick();
  await assert.rejects(() => S.shieldDepositParams('KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4', 'sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK', 'zz', '1'), /hex/); tick();

  // ── Keys, pool ids and the blind are deterministic in the master key.
  const masterSk = hex(T.feltOfInt(777));
  const account = await S.tzelAccount(masterSk);
  const keys = await S.tzelAddressKeys(account, 0);
  assert.equal(keys.pubSeed, hex(T.deriveAuthPubSeed(bytes(keys.askJ)))); tick();
  assert.deepEqual(await S.tzelAddressKeys(JSON.stringify(account), 0), keys, 'JSON or object account'); tick();
  const authDomain = hex(T.feltOfInt(99));
  const poolA = await S.tzelDepositPool(masterSk, 0, '0', authDomain, 'cd'.repeat(32), keys.pubSeed);
  const poolB = await S.tzelDepositPool(masterSk, 0, '1', authDomain, 'cd'.repeat(32), keys.pubSeed);
  assert.equal(poolA.blind, hex(T.depositBlind(bytes(masterSk), 0, 0n))); assert.notEqual(poolA.pubkeyHash, poolB.pubkeyHash);
  assert.equal(poolA.recipient, 'deposit:' + poolA.pubkeyHash); assert.equal(poolA.balanceKey, '/tzel/v1/state/deposits/balance/' + poolA.pubkeyHash); checks += 4;

  // ── An address whose tree holds the real leaf for key 5 (the rest random), so the witness
  //    builder's path check has something true to pass.
  const keyIdx = 5;
  const askJ = bytes(keys.askJ), pubSeed = bytes(keys.pubSeed);
  const leaves = Array.from({ length: T.AUTH_TREE_SIZE }, () => T.randomFelt());
  leaves[keyIdx] = T.authLeaf(askJ, pubSeed, keyIdx);
  const levels = T.authTreeLevels(pubSeed, leaves);
  const authRoot = T.authRootOf(levels);
  const authPath = T.authPath(levels, keyIdx).map(hex);
  assert.equal(hex(T.authRootFromPath(pubSeed, leaves[keyIdx], keyIdx, authPath.map(bytes))), hex(authRoot), 'authRootFromPath agrees with the levels'); tick();
  assert.equal(await S.tzelAuthLeaf(keys.askJ, keys.pubSeed, keyIdx), hex(leaves[keyIdx])); tick();
  const address = { index: 0, dJ: keys.dJ, authRoot: hex(authRoot), pubSeed: keys.pubSeed, nkTag: keys.nkTag, ekV: keys.ekV, ekD: keys.ekD };
  const myPool = await S.tzelDepositPool(masterSk, 0, '3', authDomain, address.authRoot, address.pubSeed);

  // The producer: another wallet's address 0 (its auth root is any felt here).
  const producerAccount = await S.tzelAccount(hex(T.feltOfInt(4242)));
  const producerKeys = await S.tzelAddressKeys(producerAccount, 0);
  const producerAddress = { d_j: producerKeys.dJ, auth_root: hex(T.feltOfInt(1)), auth_pub_seed: producerKeys.pubSeed, nk_tag: producerKeys.nkTag, ek_v: producerKeys.ekV, ek_d: producerKeys.ekD };

  const request = { askJ: keys.askJ, outgoingSeed: account.outgoingSeed, address, keyIdx, authPath, authDomain, pubkeyHash: myPool.pubkeyHash, blind: myPool.blind, v: '2500000', fee: '100000', producerFee: '100000', producerAddress };
  const built = await S.tzelBuildShield(request);
  assert.equal(built.witness.length, 1 + 16 + 133 + 16 + 5); assert.equal(built.witness[0], '0xaa'); checks += 2;
  assert.equal(built.witness[1], T.feltHex(bytes(authDomain))); assert.equal(built.witness[3], '0x2625a0'); assert.equal(built.witness[16], '0x5', 'key index'); checks += 3;
  assert.equal(built.publicOutputs.length, 9); assert.equal(built.publicOutputs[1], myPool.pubkeyHash); checks += 2;
  // The sighash is the fold the spec names and the signature recovers the leaf.
  const sighash = T.shieldSighash({ authDomain: bytes(authDomain), pubkeyHash: bytes(myPool.pubkeyHash), v: 2500000n, fee: 100000n, producerFee: 100000n, cmRecipient: bytes(built.clientCm), cmProducer: bytes(built.producerCm), mhRecipient: bytes(built.clientMh), mhProducer: bytes(built.producerMh) });
  assert.equal(built.sighash, hex(sighash)); tick();
  const sig = built.witness.slice(17, 17 + 133).map((h) => bytes(BigInt(h).toString(16).padStart(64, '0').match(/../g).reverse().join('')));
  assert.equal(hex(T.wotsPkToLeaf(pubSeed, keyIdx, T.recoverWotsPk(sighash, pubSeed, keyIdx, sig))), hex(leaves[keyIdx]), 'signature recovers the leaf'); tick();
  // Our own note is found by the scan and carries the outgoing record; the producer's is not ours.
  const scan = await S.tzelScan(account, [address], [{ index: 40, bytes: built.clientCm + built.clientEnc }, { index: 41, bytes: built.producerCm + built.producerEnc }]);
  assert.equal(scan.length, 1); assert.equal(scan[0].index, 40); assert.equal(scan[0].v, '2500000'); assert.equal(scan[0].rseed, built.clientRseed); assert.equal(scan[0].memo, ''); checks += 5;
  assert.equal(scan[0].nullifier, hex(T.nullifier(T.deriveNkSpend(bytes(account.nk), bytes(keys.dJ)), bytes(built.clientCm), 40))); tick();
  const recovered = T.decryptOutgoingRecovery(bytes(account.outgoingSeed), bytes(built.clientCm), T.decodeEncryptedNote(bytes(built.clientEnc)).outgoingCt);
  assert.equal(recovered.role, 'shield_output'); assert.equal(recovered.v, 2500000n); assert.equal(hex(recovered.rseed), built.clientRseed); checks += 3;
  const producerRecovered = T.decryptOutgoingRecovery(bytes(account.outgoingSeed), bytes(built.producerCm), T.decodeEncryptedNote(bytes(built.producerEnc)).outgoingCt);
  assert.equal(producerRecovered.role, 'producer_fee'); assert.equal(producerRecovered.v, 100000n); checks += 2;
  assert.equal(T.outgoingRecoveryPlaintext({ role: 'shield_output', v: 1n, rseed: T.feltOfInt(0), dJ: T.feltOfInt(0), authRoot: T.feltOfInt(0), pubSeed: T.feltOfInt(0), nkTag: T.feltOfInt(0) })[0], 1, 'role bytes are numbered from 1 as in the reference'); tick();
  assert.equal(T.outgoingRecoveryPlaintext({ role: 'unshield_change', v: 1n, rseed: T.feltOfInt(0), dJ: T.feltOfInt(0), authRoot: T.feltOfInt(0), pubSeed: T.feltOfInt(0), nkTag: T.feltOfInt(0) })[0], 5); tick();
  // A wrong pool, a wrong path or a foreign signing seed is refused before anything is signed.
  await assert.rejects(() => S.tzelBuildShield({ ...request, pubkeyHash: poolA.pubkeyHash }), /pool id/); tick();
  await assert.rejects(() => S.tzelBuildShield({ ...request, authPath: T.authPath(levels, keyIdx ^ 1).map(hex) }), /auth path/); tick();
  await assert.rejects(() => S.tzelBuildShield({ ...request, askJ: producerKeys.askJ }), /signing seed/); tick();
  await assert.rejects(() => S.tzelBuildShield({ ...request, producerFee: '0' }), /producer fee/); tick();

  // ── The message for the operator, from a (fake) proof bundle.
  const message = await S.tzelEncodeShieldMessage({ pubkeyHash: myPool.pubkeyHash, fee: '100000', v: '2500000', producerFee: '100000', proofBytes: 'aabbcc', outputPreimage: built.publicOutputs, expectedOutputs: built.publicOutputs, clientCm: built.clientCm, clientEnc: built.clientEnc, producerCm: built.producerCm, producerEnc: built.producerEnc });
  assert.equal(message.length / 2, 3 + 32 + 24 + 4 + (4 + 3 + 4 + 9 * 32) + 32 + 3455 + 32 + 3455); tick();
  assert.equal(message.slice(6, 70), myPool.pubkeyHash); tick();
  await assert.rejects(() => S.tzelEncodeShieldMessage({ pubkeyHash: myPool.pubkeyHash, fee: '100000', v: '2500000', producerFee: '100000', proofBytes: 'aa', outputPreimage: built.publicOutputs.slice(0, 8), expectedOutputs: built.publicOutputs, clientCm: built.clientCm, clientEnc: built.clientEnc, producerCm: built.producerCm, producerEnc: built.producerEnc }), /public outputs/); tick();
  // The proving service's form: the bootloader header (1 task, 12 output felts, the program hash, 9) then the nine.
  const programHash = '655b8fa9096b9d23aa8f3f722c80f776b6322831320206cbba6a1e84b00ffb00';
  const bootloader = [hex(T.feltOfInt(1)), hex(T.feltOfInt(12)), programHash, hex(T.feltOfInt(9)), ...built.publicOutputs];
  const base = { pubkeyHash: myPool.pubkeyHash, fee: '100000', v: '2500000', producerFee: '100000', proofBytes: 'aa', expectedOutputs: built.publicOutputs, clientCm: built.clientCm, clientEnc: built.clientEnc, producerCm: built.producerCm, producerEnc: built.producerEnc };
  const prefixed = await S.tzelEncodeShieldMessage({ ...base, programHash, outputPreimage: bootloader });
  assert.equal(prefixed.slice(2 * 63 + 2 * (4 + 1), 2 * 63 + 2 * (4 + 1 + 4)), '0000000d', 'thirteen output felts on the wire, as proved'); tick();
  await assert.rejects(() => S.tzelEncodeShieldMessage({ ...base, programHash: 'ab'.repeat(32), outputPreimage: bootloader }), /public outputs/); tick();
  await assert.rejects(() => S.tzelEncodeShieldMessage({ ...base, programHash, outputPreimage: [hex(T.feltOfInt(1)), hex(T.feltOfInt(12)), programHash, hex(T.feltOfInt(8)), ...built.publicOutputs] }), /public outputs/); tick();
  await assert.rejects(() => S.tzelEncodeShieldMessage({ ...base, programHash, outputPreimage: [...bootloader.slice(0, 12), built.publicOutputs[0]] }), /public outputs/); tick();

  console.log(`tzel shield: ${checks} checks passed`);
})().catch((e) => { console.error(e); process.exit(1); });
