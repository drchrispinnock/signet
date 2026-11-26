// Offline regression for FA2 token transfers (NFT Transfer and Burn): the `transfer`
// parameters are built and checked before any signer or node is touched, one call per
// contract, and a batch is sent only with exactly the per-operation limits that were approved
// (S14), the reveal inside its approved budget.
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
const plain = (value) => JSON.parse(JSON.stringify(value));

(async () => {
  const tokens = await load('tokens.js');
  const ops = await load('operations.js');
  const me = 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb';
  const them = 'tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N';
  const a = 'KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton';
  const b = 'KT1KEa8z6vWXDJrVqtMrAeDVzsvxat3kHaCE';

  // One call per contract, in order of first appearance; tokens in the order given; from_ is the source.
  const params = plain(tokens.tokenTransferParams(me, them, JSON.stringify([
    { contract: a, tokenId: '7', amount: '1' }, { contract: b, tokenId: '12', amount: '3' }, { contract: a, tokenId: '9', amount: '1' },
  ])));
  assert.equal(params.length, 2);
  assert.deepEqual(params.map((p) => [p.kind, p.to, p.amount, p.mutez]), [['transaction', a, 0, true], ['transaction', b, 0, true]]);
  const tx = (to, id, amount) => ({ prim: 'Pair', args: [{ string: to }, { prim: 'Pair', args: [{ int: id }, { int: amount }] }] });
  assert.deepEqual(params[0].parameter, { entrypoint: 'transfer', value: [{ prim: 'Pair', args: [{ string: me }, [tx(them, '7', '1'), tx(them, '9', '1')]] }] });
  assert.deepEqual(params[1].parameter, { entrypoint: 'transfer', value: [{ prim: 'Pair', args: [{ string: me }, [tx(them, '12', '3')]] }] });
  // A burn is a transfer to the burn address; a contract can receive tokens too.
  assert.equal(tokens.BURN_ADDRESS, 'tz1burnburnburnburnburnburnburjAYjjX');
  assert.equal(plain(tokens.tokenTransferParams(me, tokens.BURN_ADDRESS, [{ contract: a, tokenId: '0', amount: '1' }]))[0].parameter.value[0].args[1][0].args[0].string, tokens.BURN_ADDRESS);
  assert.equal(plain(tokens.tokenTransferParams(me, b, [{ contract: a, tokenId: '0', amount: '1' }])).length, 1);

  // Refusals, before anything else happens.
  assert.throws(() => tokens.tokenTransferParams(me, them, []), /No tokens/);
  assert.throws(() => tokens.tokenTransferParams(me, them, Array.from({ length: tokens.MAX_TOKENS_PER_TRANSFER + 1 }, () => ({ contract: a, tokenId: '1', amount: '1' }))), /At most/);
  assert.throws(() => tokens.tokenTransferParams(me, 'tz1nope', [{ contract: a, tokenId: '1', amount: '1' }]), /Not an account to send/);
  assert.throws(() => tokens.tokenTransferParams('KT1nope', them, [{ contract: a, tokenId: '1', amount: '1' }]), /Not an account/);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: me, tokenId: '1', amount: '1' }]), /Not a token contract/);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: a, tokenId: '-1', amount: '1' }]), /Not a token id/);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: a, tokenId: '01', amount: '1' }]), /Not a token id/);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: a, tokenId: 1, amount: '1' }]), /Not a token id/);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: a, tokenId: '1', amount: '0' }]), /Not an amount/);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: a, tokenId: '1', amount: '1.5' }]), /Not an amount/);
  console.log('PASS tokens: FA2 transfer parameters, one call per contract, checked before any signer or node');

  // Move Assets: the tez sweep rides last in the same group, to the same recipient, and may
  // stand alone; a malformed or unsafe amount is refused before anything else.
  const sweep = plain(tokens.tokenTransferParams(me, them, [{ contract: a, tokenId: '7', amount: '1' }, { contract: b, tokenId: '1', amount: '2' }], '1234567'));
  assert.equal(sweep.length, 3);
  assert.deepEqual(sweep[2], { kind: 'transaction', to: them, amount: 1234567, mutez: true });
  assert.deepEqual(sweep.slice(0, 2).map((p) => p.to), [a, b]);
  assert.deepEqual(plain(tokens.tokenTransferParams(me, them, [], '5')), [{ kind: 'transaction', to: them, amount: 5, mutez: true }]);
  for (const bad of ['0', '-1', '1.5', '01', '', '9007199254740993', 5]) {
    assert.throws(() => tokens.tokenTransferParams(me, them, [], bad), /Not an amount of tez/, String(bad));
  }
  assert.throws(() => tokens.tokenTransferParams(me, them, [], null), /No tokens/);
  // FA1.2: its own `transfer` per token, from the source, in order among the FA2 calls.
  const fa12 = 'KT1PWx2mnDueood7fEmfbBDKx1D9BAnnXitn';
  const mixed = plain(tokens.tokenTransferParams(me, them, [
    { contract: a, tokenId: '7', amount: '1' }, { contract: fa12, tokenId: '0', amount: '150000000', standard: 'fa1.2' }, { contract: a, tokenId: '9', amount: '2' },
  ], '5'));
  assert.deepEqual(mixed.map((p) => p.to), [a, fa12, them]);
  assert.deepEqual(mixed[1].parameter, { entrypoint: 'transfer', value: { prim: 'Pair', args: [{ string: me }, { prim: 'Pair', args: [{ string: them }, { int: '150000000' }] }] } });
  assert.equal(mixed[0].parameter.value[0].args[1].length, 2);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: fa12, tokenId: '1', amount: '1', standard: 'fa1.2' }]), /no token id/);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: fa12, tokenId: '0', amount: '1', standard: 'fa3' }]), /Not a token standard/);
  assert.throws(() => tokens.tokenTransferParams(me, them, [{ contract: fa12, tokenId: '0', amount: '1', standard: 'fa1.2' }, { contract: fa12, tokenId: '0', amount: '1' }]), /two standards/);
  console.log('PASS FA1.2: a transfer of its own per token, from the source, checked like FA2');
  console.log('PASS move assets: the tez sweep is the last operation of the group and is checked like the tokens');

  // S14 for a batch: every operation carries its own approved figures, in order.
  assert.throws(() => ops.parseBatchLimits({ operations: [] }), /not estimated/);
  assert.throws(() => ops.parseBatchLimits({ operations: [{ feeMutez: '1', gasLimit: -1, storageLimit: 0 }] }), /gas limit/);
  const limits = ops.parseBatchLimits(JSON.stringify({ operations: [{ feeMutez: '500', gasLimit: 1500, storageLimit: 0 }, { feeMutez: '700', gasLimit: 2500, storageLimit: 100 }], revealFeeMutez: '374', revealGasLimit: 200, revealStorageLimit: 0 }));
  const tx2 = (fee, gas, storage) => ({ kind: 'transaction', fee: String(fee), gas_limit: String(gas), storage_limit: String(storage) });
  const reveal = { kind: 'reveal', fee: '374', gas_limit: '200', storage_limit: '0' };
  ops.checkApprovedBatch([tx2(500, 1500, 0), tx2(700, 2500, 100)], limits);
  ops.checkApprovedBatch([reveal, tx2(500, 1500, 0), tx2(700, 2500, 100)], limits);
  assert.throws(() => ops.checkApprovedBatch([tx2(700, 2500, 100), tx2(500, 1500, 0)], limits), /Operation 1's fee/);
  assert.throws(() => ops.checkApprovedBatch([tx2(500, 1500, 0), tx2(701, 2500, 100)], limits), /Operation 2's fee/);
  assert.throws(() => ops.checkApprovedBatch([tx2(500, 1500, 0)], limits), /Expected 2 operations/);
  assert.throws(() => ops.checkApprovedBatch([tx2(500, 1500, 0), tx2(700, 2500, 100), tx2(1, 1, 1)], limits), /Expected 2 operations/);
  assert.throws(() => ops.checkApprovedBatch([tx2(500, 1500, 0), reveal], limits), /Expected 2 operations/);
  assert.throws(() => ops.checkApprovedBatch([{ ...reveal, fee: '375' }, tx2(500, 1500, 0), tx2(700, 2500, 100)], limits), /reveal would cost more/);
  assert.throws(() => ops.checkApprovedBatch([reveal, tx2(500, 1500, 0), tx2(700, 2500, 100)], ops.parseBatchLimits({ operations: limits.operations })), /reveal that was not part/);
  assert.throws(() => ops.checkApprovedBatch([], limits), /Nothing was prepared/);
  console.log('PASS S14 batch: every prepared operation must carry its own approved fee, gas and storage, in order, with the reveal inside its budget');

  // The preapply predicate, written out: a vote is accepted when its kind comes back without a
  // failed status or errors (an empty errors array counts as errors); anything else must be applied.
  const applied = { metadata: { operation_result: { status: 'applied' } } };
  const failed = { metadata: { operation_result: { status: 'failed' } } };
  assert.equal(ops.preapplyAccepted({ kind: 'transaction' }, applied), true);
  assert.equal(ops.preapplyAccepted({ kind: 'transaction' }, failed), false);
  assert.equal(ops.preapplyAccepted({ kind: 'transaction' }, { kind: 'transaction' }), false);
  assert.equal(ops.preapplyAccepted({ kind: 'transaction' }, { metadata: {} }), false);
  assert.equal(ops.preapplyAccepted({ kind: 'ballot' }, { kind: 'ballot' }), true);
  assert.equal(ops.preapplyAccepted({ kind: 'proposals' }, { kind: 'proposals', metadata: {} }), true);
  assert.equal(ops.preapplyAccepted({ kind: 'ballot' }, { kind: 'transaction' }), false);
  assert.equal(ops.preapplyAccepted({ kind: 'ballot' }, { kind: 'ballot', ...failed }), false);
  assert.equal(ops.preapplyAccepted({ kind: 'ballot' }, { kind: 'ballot', errors: [] }), false);
  assert.equal(ops.preapplyAccepted({ kind: 'ballot' }, { kind: 'ballot', errors: [{ id: 'x' }] }), false);
  assert.equal(ops.preapplyAccepted({ kind: 'ballot' }, { kind: 'ballot', errors: null }), true);
  console.log('PASS preapply: votes are accepted on an echoed kind without errors, everything else only when applied');
})().catch((e) => { console.error(e); process.exitCode = 1; });
