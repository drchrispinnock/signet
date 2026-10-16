const deadline=setTimeout(()=>{console.error('confirmation fixture deadline exceeded');process.exit(1);},10000);
const assert = require('node:assert/strict');
const {load} = require('./source-fixture.cjs');
async function fixture({record = {hash:'ooFixture', headLevel:100}, head = 102, included = 101, pass = 3, malformed = false, failure = null} = {}) {
  let saved = record, polls = 0, signalTimer, fire;
  const timerStarted = new Promise(resolve => {signalTimer = resolve;});
  const blocks = [], headers = [], writes = [], removed = [], timers = [];
  class RPC {
    constructor(url) { assert.equal(url, 'https://offline.invalid'); }
    async getBlockHeader(options) { headers.push(options?.block ?? 'head'); if (failure) throw failure; return {level: options?.block ? 100 : head}; }
    async getBlock({block}) {
      const level = Number(block); blocks.push(level);
      if (malformed) return {operations:42};
      const operations = [[],[],[],[]]; if (level === included) operations[pass].push({hash:'ooFixture'});
      return {operations};
    }
  }
  const api = await load('index.js', [['import { RpcClient } from "@taquito/rpc";', 'const RpcClient = globalThis.FixtureRPC;']], {
    FixtureRPC:RPC,
    fetch:async()=>{throw Error('fixture must never contact a network');},
    __signet:{setTimer:(id,ms)=>{assert.equal(ms,2000);polls++;timers.push(()=>fire(id));signalTimer();},clearTimer:()=>{},operationRead:()=>JSON.stringify(saved ? [saved] : []),operationSave:json=>{saved=JSON.parse(json);writes.push(saved.lastCheckedLevel);},operationRemove:hash=>{removed.push(hash);saved=null;}},
  }, context=>{fire=id=>context.__signet_timerFired(id);});
  return {api,blocks,headers,writes,removed,timers,timerStarted,record:()=>saved};
}
(async()=>{
  for (let pass=0;pass<4;pass++) {
    const f=await fixture({pass});
    assert.equal(await f.api.waitForRawOperation('https://offline.invalid','ooFixture',15),101);
    assert.deepEqual(f.blocks,[99,100,101]); assert.deepEqual(f.removed,['ooFixture']); assert.equal(f.record(),null); assert.equal(f.timers.length,0);
  }
  const resumed=await fixture({record:{hash:'ooFixture',headLevel:20,lastCheckedLevel:110},head:112,included:112});
  assert.equal(await resumed.api.waitForRawOperation('https://offline.invalid','ooFixture',15),112);
  assert.deepEqual(resumed.blocks,[109,110,111,112]);
  const legacy=await fixture({record:{hash:'ooFixture',branch:'Bfixture'},head:101,included:101});
  assert.equal(await legacy.api.waitForRawOperation('https://offline.invalid','ooFixture',15),101);
  assert.deepEqual(legacy.headers,['Bfixture','head']);
  const exhausted=await fixture({head:115,included:null});
  const outcome=exhausted.api.waitForRawOperation('https://offline.invalid','ooFixture',15);
  let rejected; const observed=outcome.catch(error=>{rejected=error;});
  // No wall-clock sleep: let the promise chain reach its controlled polling timer.
  await exhausted.timerStarted;
  assert.equal(exhausted.timers.length,1); exhausted.timers.shift()(); await observed;
  assert.match(rejected.message,/not seen in 15 blocks/);
  assert.deepEqual(exhausted.writes,[112,115]); assert.equal(exhausted.record().lastCheckedLevel,115); assert.deepEqual(exhausted.removed,[]);
  const malformed=await fixture({malformed:true});
  await assert.rejects(malformed.api.waitForRawOperation('https://offline.invalid','ooFixture',15)); assert.deepEqual(malformed.removed,[]);
  const failed=await fixture({failure:Error('offline fixture RPC failure')});
  await assert.rejects(failed.api.waitForRawOperation('https://offline.invalid','ooFixture',15),/offline fixture RPC failure/); assert.deepEqual(failed.removed,[]);
  const compatibility=await fixture();
  await assert.rejects(compatibility.api.waitForConfirmation('ooFixture',1),/unknown operation ooFixture/);
  clearTimeout(deadline);
  console.log('PASS F17: all inclusion passes, resume/legacy cursors, exhaustion, journal updates/removal, malformed/RPC failures and legacy export');
})().catch(error=>{clearTimeout(deadline);console.error(error);process.exitCode=1;});
