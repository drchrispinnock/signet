// Offline regression: a recovery record whose signed bytes can never be applied again (counter
// used, or branch expired) is forgotten instead of holding Send and every new signature forever.
const deadline=setTimeout(()=>{console.error('pending recovery fixture deadline exceeded');process.exit(1);},10000);
const assert = require('node:assert/strict');
const {localForger} = require('@taquito/local-forging');
const {b58Encode, PrefixV2, encodeOpHash} = require('@taquito/utils');
const {InMemorySigner} = require('@taquito/signer');
const {load} = require('./source-fixture.cjs');
const source = 'tz1gUCWWwmwEpc7eVd4NHy3UhL28K4j9L6jy';
let publicKey;
async function signedRecord(extra = {}) {
  publicKey ??= await new InMemorySigner(b58Encode(new Uint8Array(32).fill(7), PrefixV2.Ed25519Seed)).publicKey();
  const branch = b58Encode(new Uint8Array(32).fill(1), PrefixV2.BlockHash);
  const contents = [{kind:'reveal',source,public_key:publicKey,fee:'300',counter:'41',gas_limit:'10000',storage_limit:'0'},
    {kind:'transaction',source,fee:'1343',counter:'42',gas_limit:'10499',storage_limit:'0',amount:'3000000',destination:'tz1burnburnburnburnburnburnburjAYjjX'}];
  const signedBytes = await localForger.forge({branch, contents}) + '00'.repeat(64);
  return {hash:encodeOpHash(signedBytes), source, chainID:'NetFixture', branch, contents, signedBytes, injected:false, rpcURL:'https://offline.invalid', ...extra};
}
async function fixture(record, {counter = '40', head = 1000, ttl = 450, failure = null} = {}) {
  const journal = new Map([[record.hash, record]]), calls = [];
  class RPC {
    constructor(url) { assert.equal(url, 'https://offline.invalid'); }
    async getChainId() { return 'NetFixture'; }
    async getContract(address) { calls.push('contract'); assert.equal(address, source); if (failure) throw failure; return {counter, balance:'0'}; }
    async getBlockHeader() { calls.push('header'); return {level:head}; }
    async getBlockMetadata() { calls.push('metadata'); return {max_operations_ttl:ttl}; }
  }
  const api = await load('operations.js', [['import { RpcClient } from "@taquito/rpc";', 'const RpcClient = globalThis.FixtureRPC;']], {
    FixtureRPC:RPC,
    fetch:async()=>{throw Error('fixture must never contact a network');},
    __signet:{operationRead:()=>JSON.stringify([...journal.values()]),operationSave:json=>{const r=JSON.parse(json);journal.set(r.hash,r);return '';},operationRemove:hash=>{journal.delete(hash);return '';}},
  });
  return {api, journal, calls};
}
(async()=>{
  // Live: counter not reached, head within the operation's lifetime. Kept, and it still blocks signing.
  const live = await fixture(await signedRecord({headLevel:900}));
  assert.equal((await live.api.pendingOperation('https://offline.invalid', source)).hash, [...live.journal.keys()][0]);
  await assert.rejects(live.api.assertNoPending('https://offline.invalid', source), /still needs recovery/);
  assert.equal(live.journal.size, 1);
  // Counter reached the first counter of the batch (included, or used by something else): forgotten.
  for (const counter of ['41', '42', '33393579']) {
    const used = await fixture(await signedRecord({headLevel:900}), {counter});
    assert.equal(await used.api.pendingOperation('https://offline.invalid', source), null);
    assert.equal(used.journal.size, 0); assert.deepEqual(used.calls, ['contract']);
  }
  // Counter untouched but the branch expired: never included and never can be. Forgotten, and signing is free again.
  const expired = await fixture(await signedRecord({headLevel:500}), {head:951, ttl:450});
  assert.equal(await expired.api.assertNoPending('https://offline.invalid', source), 'NetFixture');
  assert.equal(expired.journal.size, 0);
  const edge = await fixture(await signedRecord({headLevel:500}), {head:950, ttl:450});
  assert.notEqual(await edge.api.pendingOperation('https://offline.invalid', source), null); assert.equal(edge.journal.size, 1);
  // Doubt keeps the record: a failed read, a record without a head level, an odd lifetime or counter.
  const offline = await fixture(await signedRecord({headLevel:1}), {failure:Error('offline fixture RPC failure')});
  assert.notEqual(await offline.api.pendingOperation('https://offline.invalid', source), null); assert.equal(offline.journal.size, 1);
  const legacy = await fixture(await signedRecord(), {head:10**6});
  assert.notEqual(await legacy.api.pendingOperation('https://offline.invalid', source), null); assert.deepEqual(legacy.calls, ['contract']);
  const oddTTL = await fixture(await signedRecord({headLevel:1}), {ttl:'450'});
  assert.notEqual(await oddTTL.api.pendingOperation('https://offline.invalid', source), null); assert.equal(oddTTL.journal.size, 1);
  const oddCounter = await fixture(await signedRecord({headLevel:900}), {counter:99});
  assert.notEqual(await oddCounter.api.pendingOperation('https://offline.invalid', source), null); assert.equal(oddCounter.journal.size, 1);
  // A tampered record is still refused before anything is forgotten.
  const tampered = await fixture({...await signedRecord({headLevel:500}), signedBytes:'ab'.repeat(200)}, {counter:'42'});
  await assert.rejects(tampered.api.pendingOperation('https://offline.invalid', source), /hash/); assert.equal(tampered.journal.size, 1);
  clearTimeout(deadline);
  console.log('PASS pending recovery: live records kept, used counters and expired branches forgotten, doubt and tampering keep the record');
})().catch(error=>{clearTimeout(deadline);console.error(error);process.exitCode=1;});
