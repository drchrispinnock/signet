// Offline regression for Etherlink governance: the entrypoint parameters are checked before
// any signer or node is touched, the view and list replies are read strictly, and the current
// period is derived from the view plus a possibly stale storage context exactly as the
// contract's own get_voting_state does (baking-bad/etherlink-governance, voting.mligo).
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

// Values cross the vm realm boundary, so they are compared by structure, not prototype.
const plain = (value) => JSON.parse(JSON.stringify(value));

(async () => {
  const gov = await load('etherlink-governance.js');
  const contract = 'KT19oUVQPnVLuUBYXrBVd46WJnNAMpqkKSwo';
  const hash = '009e07373751a43acbf0cd747b404f45130e0ad561c4b7da937e02eb812bd0f7e8';

  // Parameters: a 33-byte kernel hash as bytes, a vote as one of three words, nothing else.
  assert.deepEqual(plain(gov.governanceParams(contract, 'new_proposal', '0x' + hash.toUpperCase())), { to: contract, amount: 0, mutez: true, parameter: { entrypoint: 'new_proposal', value: { bytes: hash } } });
  assert.deepEqual(plain(gov.governanceParams(contract, 'upvote_proposal', hash).parameter), { entrypoint: 'upvote_proposal', value: { bytes: hash } });
  assert.deepEqual(plain(gov.governanceParams(contract, 'vote', 'pass').parameter), { entrypoint: 'vote', value: { string: 'pass' } });
  for (const bad of [hash.slice(2), hash + '00', 'zz' + hash.slice(2), '']) assert.throws(() => gov.governanceParams(contract, 'upvote_proposal', bad), /33 bytes/, bad);
  for (const bad of ['yay', 'Yea', '', null]) assert.throws(() => gov.governanceParams(contract, 'vote', bad), /one of yea, nay, pass/, String(bad));
  assert.throws(() => gov.governanceParams(contract, 'trigger_kernel_upgrade', 'sr1x'), /Unknown governance entrypoint/);
  assert.throws(() => gov.governanceParams('tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb', 'vote', 'yea'), /Not a governance contract/);
  const limits = JSON.stringify({ feeMutez: '1000', gasLimit: 1000, storageLimit: 0 });
  await assert.rejects(gov.sendEtherlinkGovernance('https://offline.invalid', '{}', contract, 'vote', 'maybe', limits), /one of yea, nay, pass/);
  await assert.rejects(gov.estimateEtherlinkGovernance('https://offline.invalid', 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb', 'edpk', 'KT1nonsense', 'vote', 'yea'), /Not a governance contract/);
  console.log('PASS governance parameters are checked before any signer or node is touched');

  // The period from the contract's config and a level, as its get_voting_state computes it:
  // mainnet's fast contract answered period 816 with 3791 blocks left at level 15558098.
  const fast = { started_at_level: '11640289', period_length: '4800' };
  assert.deepEqual(plain(gov.periodAt(fast, 15558098)), { index: 816, remaining: 3791 });
  assert.deepEqual(plain(gov.periodAt(fast, 11640289)), { index: 0, remaining: 4800 });
  assert.deepEqual(plain(gov.periodAt(fast, 11640289 + 4799)), { index: 0, remaining: 1 });
  assert.deepEqual(plain(gov.periodAt(fast, 11640289 + 4800)), { index: 1, remaining: 4800 });
  assert.throws(() => gov.periodAt(fast, 11640288), /not started/);
  assert.throws(() => gov.periodAt({ started_at_level: '1', period_length: '0' }, 5), /period length/);
  assert.throws(() => gov.periodAt({ started_at_level: '-1', period_length: '10' }, 5), /natural number/);
  console.log('PASS the period is computed from the contract\'s config as its view does');

  // Voting rights from one voting_delegations entry, as list_voters answers them: granted, and
  // for every contract or a set naming this one. Both Taquito shapes of the pair are read.
  const other = 'KT1AXRU3wLc87WNhLhVGrgqDGubLACUMUgPb';
  const entry = new Map([
    ['tz3ipHZQpBBFuxv7eKoFgGnTaU3RBhnS93yY', { 0: true, 1: null }],
    ['tz3iY4BXVpKC6JQ3KB7pwHKa1SVpitcfM4p2', { 0: true, 1: [contract] }],
    ['tz3h7UCrLoFih8nrStVy8GcChtZiVuu1mDYD', { 0: true, 1: [other] }],
    ['tz3cqThj23Feu55KDynm7Vg81mCMpWDgzQZq', { 0: false, 1: null }],
    ['tz3XPXVG3rmMp7xioPNdj7DyUsFsTFwaG3Ws', { bool: true, set: new Set([other, contract]) }],
  ]);
  assert.deepEqual(plain(gov.votersFrom(entry, contract)), ['tz3XPXVG3rmMp7xioPNdj7DyUsFsTFwaG3Ws', 'tz3iY4BXVpKC6JQ3KB7pwHKa1SVpitcfM4p2', 'tz3ipHZQpBBFuxv7eKoFgGnTaU3RBhnS93yY']);
  assert.deepEqual(plain(gov.votersFrom(entry, other)), ['tz3XPXVG3rmMp7xioPNdj7DyUsFsTFwaG3Ws', 'tz3h7UCrLoFih8nrStVy8GcChtZiVuu1mDYD', 'tz3ipHZQpBBFuxv7eKoFgGnTaU3RBhnS93yY']);
  assert.deepEqual(plain(gov.votersFrom({ tz1iuWAe6hYCewe1N7me6aekitsH6fFE3i4P: { bool: true, set: null } }, contract)), ['tz1iuWAe6hYCewe1N7me6aekitsH6fFE3i4P']);
  assert.deepEqual(plain(gov.votersFrom({ tz1iuWAe6hYCewe1N7me6aekitsH6fFE3i4P: { 0: true, 1: { Some: [other] } } }, contract)), []);
  assert.deepEqual(plain(gov.votersFrom(null, contract)), []);
  assert.deepEqual(plain(gov.votersFrom(new Map(), contract)), []);
  console.log('PASS voting rights are read from the delegation entry as list_voters answers them');

  // Deriving the period from the view and a stale or current storage context.
  const proposal = { total_voting_power: '600', winner_candidate: hash, max_upvotes_voting_power: '50' };
  const promotion = { total_voting_power: '700', winner_candidate: hash, yea_voting_power: '10', nay_voting_power: '20', pass_voting_power: '30' };
  let d = gov.deriveState({ index: 816, kind: 'proposal', remaining: 3780 }, { period_index: '816', period: { proposal } }, '999');
  assert.equal(d.current, 'proposal'); assert.equal(d.totalVotingPower, '600'); assert.equal(d.candidate, null);
  d = gov.deriveState({ index: 817, kind: 'proposal', remaining: 4800 }, { period_index: '816', period: { proposal } }, '999');
  assert.equal(d.current, null); assert.equal(d.totalVotingPower, '999');   // a fresh period nobody has touched
  d = gov.deriveState({ index: 817, kind: 'proposal', remaining: 4800 }, null, '999');
  assert.equal(d.current, null); assert.equal(d.periodKind, 'proposal'); assert.equal(d.remainingBlocks, 4800);
  d = gov.deriveState({ index: 42, kind: 'promotion', remaining: 100 }, { period_index: '42', period: { promotion } }, '999');
  assert.equal(d.current, 'promotion'); assert.equal(d.candidate, '0x' + hash); assert.deepEqual(plain(d.tallies), { yea: '10', nay: '20', pass: '30' }); assert.equal(d.totalVotingPower, '700');
  d = gov.deriveState({ index: 42, kind: 'promotion', remaining: 100 }, { period_index: '41', period: { proposal } }, '999');
  assert.equal(d.current, null); assert.equal(d.candidate, '0x' + hash); assert.deepEqual(plain(d.tallies), { yea: '0', nay: '0', pass: '0' }); assert.equal(d.totalVotingPower, '999');
  // Taquito hands an option of a record over as { Some: record }, with option fields bare or null.
  d = gov.deriveState({ index: 42, kind: 'promotion', remaining: 100 }, { Some: { period_index: '42', period: { promotion } } }, '999');
  assert.equal(d.current, 'promotion'); assert.equal(d.candidate, '0x' + hash);
  d = gov.deriveState({ index: 42, kind: 'promotion', remaining: 100 }, { Some: { period_index: '41', period: { proposal: { ...proposal, winner_candidate: { Some: hash } } } } }, '999');
  assert.equal(d.current, null); assert.equal(d.candidate, '0x' + hash);
  assert.throws(() => gov.deriveState({ index: 42, kind: 'promotion', remaining: 100 }, { period_index: '40', period: { proposal } }, '999'), /does not match/);
  assert.throws(() => gov.deriveState({ index: 42, kind: 'promotion', remaining: 100 }, { period_index: '41', period: { proposal: { ...proposal, winner_candidate: null } } }, '999'), /does not match/);
  assert.throws(() => gov.deriveState({ index: 42, kind: 'promotion', remaining: 100 }, null, '999'), /does not match/);
  assert.throws(() => gov.deriveState({ index: 42, kind: 'promotion', remaining: 100 }, { period_index: '42', period: { promotion: { ...promotion, yea_voting_power: '-1' } } }, '999'), /natural number/);
  console.log('PASS the current period is derived from the computed period and a possibly stale storage context');
})().catch((error) => { console.error(error); process.exit(1); });
