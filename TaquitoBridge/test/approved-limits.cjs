// Offline regression (S14, S15): a native send carries exactly the approved fee, gas and storage,
// and a lost injection reply is reported as an unknown outcome with the operation hash, never
// as a failure to retry with a fresh operation.
const fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {encodeOpHash}=require('@taquito/utils');
let mode='ok',injections=0,failSave=false;const journal=new Map();
const ctx={console:{log(){},warn(){},error(){},info(){},debug(){}},__signet:{randomBytes:n=>Array.from(crypto.randomBytes(n)),operationRead(){return JSON.stringify([...journal.values()]);},operationSave(json){if(failSave)return "synthetic disk failure";const record=JSON.parse(json);journal.set(record.hash,record);return "";},operationRemove(hash){journal.delete(hash);return "";},setTimer(){},clearTimer(){},cancelFetch(){},storageGet(){return null},storageSet(){},storageDelete(){},octezConnectEvent(){},fetch(id,url,method,headers,body){
 Promise.resolve().then(()=>{if(url.endsWith('/chain_id'))return ctx.__signet_fetchDone(id,200,'OK','{}','"NetFixture"',null);if(url.endsWith('/blocks/head/header'))return ctx.__signet_fetchDone(id,200,'OK','{}','{"level":100,"timestamp":"2026-10-12T00:00:00Z"}',null);assert.ok(url.includes('/injection/operation'),url);injections++;assert.ok(journal.has(encodeOpHash(JSON.parse(body))),"signed bytes must be durably recorded before injection");
  if(mode==='lost')return ctx.__signet_fetchDone(id,0,'','{}','','The network connection was lost.');
  if(mode==='gateway')return ctx.__signet_fetchDone(id,504,'Gateway Timeout','{}','<html>forwarded upstream, timed out</html>',null);
  if(mode==='wrongHash')return ctx.__signet_fetchDone(id,200,'OK','{}',JSON.stringify('ooWRONG'),null);
  if(mode==='rejected')return ctx.__signet_fetchDone(id,500,'Internal Server Error','{}','[{"kind":"permanent","id":"proto.alpha.contract.counter_in_the_past"}]',null);
  ctx.__signet_fetchDone(id,200,'OK','{}',JSON.stringify(encodeOpHash(JSON.parse(body))),null);});
}}};vm.createContext(ctx);vm.runInContext(fs.readFileSync(require('node:path').resolve(__dirname,'../../Signet/Resources/taquito-bridge.js'),'utf8'),ctx);const api=ctx.TaquitoBridge;

// S14: approved limits are the only limits.
assert.throws(()=>api.parseLimits('{"feeMutez":-1,"gasLimit":1,"storageLimit":0}'),/fee/);
assert.throws(()=>api.parseLimits('{"feeMutez":"1e3","gasLimit":1.5,"storageLimit":0}'));
assert.throws(()=>api.parseLimits(null),/not estimated/);
const limits=api.parseLimits({feeMutez:'500',gasLimit:1500,storageLimit:257,revealFeeMutez:'374',revealGasLimit:200,revealStorageLimit:0});
const tx=(fee,gas,storage)=>({kind:'transaction',fee:String(fee),gas_limit:String(gas),storage_limit:String(storage)});
api.checkApproved([tx(500,1500,257)],limits);
api.checkApproved([{kind:'reveal',fee:'374',gas_limit:'200',storage_limit:'0'},tx(500,1500,257)],limits);
assert.throws(()=>api.checkApproved([tx(501,1500,257)],limits),/not what was approved/);
assert.throws(()=>api.checkApproved([tx(500,1501,257)],limits),/not what was approved/);
assert.throws(()=>api.checkApproved([tx(500,1500,258)],limits),/not what was approved/);
assert.throws(()=>api.checkApproved([{kind:'reveal',fee:'375',gas_limit:'200',storage_limit:'0'},tx(500,1500,257)],limits),/reveal would cost more/);
assert.throws(()=>api.checkApproved([{kind:'reveal',fee:'374',gas_limit:'200',storage_limit:'0'},tx(500,1500,257)],api.parseLimits({feeMutez:'500',gasLimit:1500,storageLimit:257})),/reveal that was not part/);
assert.throws(()=>api.checkApproved([tx(500,1500,257),tx(500,1500,257)],limits),/Expected one operation/);
assert.throws(()=>api.checkApproved([],limits));
console.log('PASS S14: prepared contents must carry exactly the approved fee, gas and storage, with the reveal inside its approved budget');

// S15: injection outcomes.
(async()=>{
const sbytes='ab'.repeat(32+40+64);
const ok=await api.injectSignedBytes('https://offline.invalid',sbytes);assert.equal(journal.get(ok.hash).headLevel,100,"the head level at injection is recorded so a watcher can scan by level");
assert.equal(ok.injected,true);assert.equal(ok.hash,encodeOpHash(sbytes));assert.equal(ok.signedBytes,sbytes);
mode='lost';const lost=await api.injectSignedBytes('https://offline.invalid',sbytes);
assert.equal(lost.injected,false);assert.equal(lost.hash,encodeOpHash(sbytes),'the hash is known before the node answers');assert.equal(lost.signedBytes,sbytes);
mode='rejected';const uncertain=await api.injectSignedBytes('https://offline.invalid',sbytes);assert.equal(uncertain.injected,false);assert.equal(uncertain.signedBytes,sbytes);
await assert.rejects(api.injectSignedBytes('https://offline.invalid','zz'),/not a signed operation/);
mode='gateway';const gateway=await api.injectSignedBytes('https://offline.invalid',sbytes);assert.equal(gateway.injected,false);assert.equal(gateway.hash,encodeOpHash(sbytes));
mode='wrongHash';const wrong=await api.injectSignedBytes('https://offline.invalid',sbytes);assert.equal(wrong.injected,false);assert.equal(wrong.hash,encodeOpHash(sbytes));
failSave=true;const before=injections;await assert.rejects(api.injectSignedBytes('https://offline.invalid',sbytes),/disk failure/);assert.equal(injections,before);
assert.equal(injections,5);
console.log('PASS S15: a lost reply yields the hash with injected:false; a post-injection error remains uncertain; rebroadcast resends the same bytes');
})().catch(e=>{console.error(e);process.exitCode=1});
