// Offline: the AirGap Vault signer hands only operation bytes to Swift and uses a signature
// only when it verifies against the account's key over blake2b(0x03 ‖ bytes).
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {load} = require('./source-fixture.cjs');
const {b58Encode, getPkhfromPk, PrefixV2} = require('@tezos-x/octez.js-utils');
const {blake2b} = require('@noble/hashes/blake2.js');
(async()=>{
  const {publicKey: pub, privateKey} = crypto.generateKeyPairSync('ed25519');
  const raw = pub.export({format:'der',type:'spki'}).subarray(-32);
  const edpk = b58Encode(raw, PrefixV2.Ed25519PublicKey), address = getPkhfromPk(edpk);
  const other = getPkhfromPk(b58Encode(crypto.generateKeyPairSync('ed25519').publicKey.export({format:'der',type:'spki'}).subarray(-32), PrefixV2.Ed25519PublicKey));
  const forged = 'ab'.repeat(40) + '6c00';
  const signHex = hex => crypto.sign(null, blake2b(Buffer.from('03' + hex, 'hex'), {dkLen: 32}), privateKey).toString('hex');
  let asked = [], reply = () => ({sig: signHex(forged)});
  const globals = {__signet: {airgapSign(id, json) { asked.push(JSON.parse(json)); const r = reply(); Promise.resolve().then(() => api.__done(id, r.sig ?? '', r.error ?? null)); }}};
  const api = await load('airgap.js', [], globals, ctx => { api_ctx = ctx; });
  var api_ctx; api.__done = (...a) => api_ctx.__signet_airgapDone(...a);

  assert.throws(() => api.airGapSignerFor({publicKey: edpk, address: other}), /derives/);
  assert.throws(() => api.airGapSignerFor({publicKey: 'nope', address}), /edpk/);
  const signer = api.airGapSignerFor({publicKey: edpk, address});
  assert.equal(await signer.publicKey(), edpk);
  assert.equal(await signer.publicKeyHash(), address);

  const signed = await signer.sign(forged, new Uint8Array([3]));
  assert.deepStrictEqual(asked, [{address, publicKey: edpk, forged}]);
  assert.equal(signed.sbytes, forged + signHex(forged));
  assert.ok(signed.prefixSig.startsWith('edsig') && signed.sig.startsWith('sig'));
  console.log('PASS AirGap: operation bytes go to the Vault and its verified signature comes back');

  asked = [];
  await assert.rejects(signer.sign('05' + forged), /operations only/);
  await assert.rejects(signer.sign(forged, new Uint8Array([5])), /operations only/);
  assert.deepStrictEqual(asked, []);
  console.log('PASS AirGap: messages and other watermarks never reach the Vault');

  reply = () => ({sig: signHex(forged + '00')});
  await assert.rejects(signer.sign(forged, new Uint8Array([3])), /not valid for this account/);
  reply = () => ({sig: 'cd'.repeat(10)});
  await assert.rejects(signer.sign(forged, new Uint8Array([3])), /no usable signature/);
  reply = () => ({error: 'Signing in AirGap Vault was cancelled.'});
  await assert.rejects(signer.sign(forged, new Uint8Array([3])), /cancelled/);
  console.log('PASS AirGap: a wrong, short or cancelled reply is refused');
})().catch(e => { console.error(e); process.exit(1); });
