// Offline regression for the Etherlink bridge: the routing data for a Michelson-interface
// deposit must be byte-for-byte what baking-bad's xtz_deposit_michelson.py produces
// (`0x01 ++ rlp([[0x01, forged tz address], []])`), and parameters are checked before any
// signer or node is touched. Expected vectors were derived independently (base58 decode of the
// address plus the RLP spec), not from this code.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const crypto = require('node:crypto');
const { build } = require('esbuild');

async function load(file) {
  const source = fs.readFileSync(path.resolve(__dirname, '../src', file), 'utf8');
  const result = await build({ stdin: { contents: source, resolveDir: path.resolve(__dirname, '../src'), sourcefile: file }, bundle: true, write: false, format: 'iife', globalName: 'API', platform: 'browser', target: 'safari17' });
  const context = { console: { log() {}, warn() {}, error() {} }, Buffer, URL, Headers, Request, Response, TextEncoder, TextDecoder, crypto: crypto.webcrypto, setTimeout, clearTimeout,
    fetch: async () => { throw new Error('network prohibited'); }, __signet: {} };
  vm.createContext(context); vm.runInContext(result.outputFiles[0].text, context); return context.API;
}

(async () => {
  const bridge = await load('bridge.js');
  const vectors = {
    tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb: '01dad8019600006b82198cb179e8306c1bedd08f12dc863f328886c0',
    tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq: '01dad8019600012031d34105bb1243b973e06139193221110a0ca1c0',
    tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5: '01dad8019600026fde46af0356a0476dae4e4600172dc9309b3aa4c0',
  };
  for (const [address, expected] of Object.entries(vectors)) assert.equal(bridge.michelsonRoutingData(address), expected, address);
  // The rollup has no tz4 yet and refuses contracts; nothing else is a receiver.
  for (const bad of ['tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm', 'KT1Mkqf6TnMVmhAAuBJCizkzAu4Nhg6DTPmM', 'tz1short', '']) {
    assert.throws(() => bridge.michelsonRoutingData(bad), /tz1, tz2 or tz3/, bad);
  }
  console.log('PASS 0.9.1: Michelson-interface deposit routing data matches the reference encoding; tz4 and KT1 receivers are refused');

  // Parameters are checked before the signer is built or the node is contacted.
  const good = ['KT19aBsSWvWtvEkbiqReJnD8UzQMWcD8SHUD', 'sr19fMYrr5C4qqvQqQrDSjtP31GcrWjodzvg', 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb'];
  const limits = JSON.stringify({ feeMutez: '1000', gasLimit: 1000, storageLimit: 0 });
  await assert.rejects(bridge.sendEtherlinkDeposit('https://offline.invalid', '{}', 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb', good[1], good[2], '1000000', limits), /Not a bridge contract/);
  await assert.rejects(bridge.sendEtherlinkDeposit('https://offline.invalid', '{}', good[0], 'KT19aBsSWvWtvEkbiqReJnD8UzQMWcD8SHUD', good[2], '1000000', limits), /Not a Smart Rollup/);
  await assert.rejects(bridge.sendEtherlinkDeposit('https://offline.invalid', '{}', good[0], good[1], good[2], '0', limits), /Invalid deposit amount/);
  await assert.rejects(bridge.sendEtherlinkDeposit('https://offline.invalid', '{}', good[0], good[1], good[2], '1.5', limits), /Invalid deposit amount/);
  await assert.rejects(bridge.estimateEtherlinkDeposit('https://offline.invalid', good[2], 'edpk', good[0], good[1], 'tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm', '1000000'), /tz1, tz2 or tz3/);
  console.log('PASS 0.9.1: bridge, rollup, receiver and amount are validated before signing or contacting a node');

  // Linking: the gateway call is a zero-tez `%call_evm` no-op from the account itself, checked before any signer or node.
  const link = bridge.linkParams(bridge.ETHERLINK_GATEWAY);
  assert.equal(link.to, 'KT18oDJJKXMKhfE1bSuAPGp92pYcwVDiqsPw');
  assert.equal(link.amount, 0);
  assert.equal(link.parameter.entrypoint, 'call_evm');
  assert.equal(JSON.stringify(link.parameter.value), JSON.stringify({ prim: 'Pair', args: [{ string: '0x000000000000000000000000000000000000dEaD' }, { string: 'ping()' }, { bytes: '' }, { prim: 'None' }] }));
  for (const bad of ['tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb', 'KT1short', '']) assert.throws(() => bridge.linkParams(bad), /Not a gateway contract/);
  await assert.rejects(bridge.sendEtherlinkLink('https://offline.invalid', JSON.stringify({ kind: 'secret', key: 'edsk', address: 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb' }), 'KT1short', '{}'), /Not a gateway contract/);
  console.log('PASS 0.9.3: the Etherlink link call targets the gateway with a zero-tez no-op and refuses a bad gateway before signing');
})().catch((error) => { console.error('FAIL', error); process.exit(1); });
