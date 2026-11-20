// Offline: a remote signer's signature, base58 or raw, is put in the key's form and used only
// when it verifies against the account's key; Swift is asked with the watermark in front.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {load} = require('./source-fixture.cjs');
const {b58Encode, getPkhfromPk, PrefixV2} = require('@tezos-x/octez.js-utils');
const {blake2b} = require('@noble/hashes/blake2.js');
(async()=>{
  const {publicKey: pub, privateKey} = crypto.generateKeyPairSync('ed25519');
  const edpk = b58Encode(pub.export({format:'der',type:'spki'}).subarray(-32), PrefixV2.Ed25519PublicKey), address = getPkhfromPk(edpk);
  const signHex = hex => crypto.sign(null, blake2b(Buffer.from(hex, 'hex'), {dkLen: 32}), privateKey);
  const forged = 'ab'.repeat(40) + '6c00';
  let asked = [], reply = req => JSON.stringify({raw: signHex(req.bytes).toString('hex')});
  let ctx;
  const globals = {__signet: {remoteSign(id, json) { const req = JSON.parse(json); asked.push(req); let r, e = null; try { r = reply(req); } catch (x) { e = x.message; } Promise.resolve().then(() => ctx.__signet_remoteDone(id, r ?? '', e)); }}};
  const api = await load('remote.js', [], globals, c => { ctx = c; });
  const locator = `tcp://localhost:7732/${address}`;

  assert.throws(() => api.remoteSignerFor({locator, publicKey: edpk, address: 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb'}), /derives/);
  assert.throws(() => api.remoteSignerFor({publicKey: edpk, address}), /locator/);
  const signer = api.remoteSignerFor({locator, publicKey: edpk, address});

  const op = await signer.sign(forged, new Uint8Array([3]));
  assert.deepStrictEqual(asked, [{op: 'sign', locator, address, bytes: '03' + forged}]);
  assert.equal(op.sbytes, forged + signHex('03' + forged).toString('hex'));
  assert.ok(op.prefixSig.startsWith('edsig'));
  console.log('PASS remote: an operation goes out with its watermark and a raw signature comes back verified');

  // The HTTP signer answers in base58, often the generic sig… form.
  reply = req => JSON.stringify({signature: b58Encode(signHex(req.bytes), PrefixV2.GenericSignature)});
  const payload = '05' + '0100000003616263';
  const message = await signer.sign(payload);
  assert.equal(asked.at(-1).bytes, payload);
  assert.equal(message.prefixSig, b58Encode(signHex(payload), PrefixV2.Ed25519Signature));
  reply = req => JSON.stringify({signature: b58Encode(signHex(req.bytes), PrefixV2.Ed25519Signature)});
  assert.equal((await signer.sign(forged, new Uint8Array([3]))).sbytes, forged + signHex('03' + forged).toString('hex'));
  console.log('PASS remote: a base58 signature (generic or edsig) is accepted for a raw payload and an operation');

  reply = req => JSON.stringify({raw: signHex(req.bytes + '00').toString('hex')});
  await assert.rejects(signer.sign(forged, new Uint8Array([3])), /not valid for this account/);
  reply = () => JSON.stringify({raw: 'cd'.repeat(10)});
  await assert.rejects(signer.sign(forged, new Uint8Array([3])), /wrong length/);
  reply = () => JSON.stringify({signature: 'nonsense'});
  await assert.rejects(signer.sign(forged, new Uint8Array([3])), /could not be read/);
  reply = () => { throw new Error('The remote signer refused the request: unknown_key'); };
  await assert.rejects(signer.sign(forged, new Uint8Array([3])), /unknown_key/);
  await assert.rejects(signer.provePossession(), /Only BLS/);
  console.log('PASS remote: a wrong, short, unreadable or refused signature is not used');
})().catch(e => { console.error(e); process.exit(1); });
