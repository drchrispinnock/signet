// Offline regression: a dApp approval must bind every signed operation, including its reveal.
const fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const req=require;const {InMemorySigner}=req('@taquito/signer');const {b58Encode,PrefixV2}=req('@taquito/utils');const {localForger}=req('@taquito/local-forging');
let operation,expectedSigned,preapplies=0,injections=0,mode='honest';
const ctx={console:{log(){},warn(){},error(){},info(){},debug(){}},__signet:{randomBytes:n=>Array.from(crypto.randomBytes(n)),setTimer(){},clearTimer(){},cancelFetch(){},storageGet(){return null},storageSet(){},storageDelete(){},octezConnectEvent(){},fetch(id,url,method,headers,body){
 Promise.resolve().then(()=>{assert.equal(new URL(url).hostname,'offline.invalid');const data=JSON.parse(body);
 if(url.endsWith('/preapply/operations')){preapplies++;assert.deepEqual(data[0].contents,operation.contents);return mode==='empty'?[]:[{contents:operation.contents.map(c=>({...c,metadata:{operation_result:{status:mode==='failed'?'failed':'applied'}}}))}];}
 if(url.includes('/injection/operation')){injections++;assert.equal(data,expectedSigned);return 'ooOFFLINE';}throw Error('Unexpected RPC/re-estimation '+url);
 }).then(data=>ctx.__signet_fetchDone(id,200,'OK','{}',JSON.stringify(data),null),e=>ctx.__signet_fetchDone(id,0,'','{}','',e.message));
}}};vm.createContext(ctx);vm.runInContext(fs.readFileSync(require('node:path').resolve(__dirname, '../../Signet/Resources/taquito-bridge.js'),'utf8'),ctx);const api=ctx.TaquitoBridge;
(async()=>{
const secret=b58Encode(new Uint8Array(32).fill(7),PrefixV2.Ed25519Seed),signer=new InMemorySigner(secret),source=await signer.publicKeyHash(),publicKey=await signer.publicKey();const spec=JSON.stringify({kind:'secret',secretKey:secret,address:source});
operation={branch:b58Encode(new Uint8Array(32),PrefixV2.BlockHash),protocol:'mock-protocol',contents:[{kind:'reveal',source,public_key:publicKey,fee:'999',gas_limit:'10000',storage_limit:'0',counter:'1'},{kind:'transaction',source,destination:'KT1UqzPQCEb6bVYKeab9EXjVcQsUGT8iLC2m',amount:'0',fee:'500',gas_limit:'1500',storage_limit:'0',counter:'2'}]};
const ops=JSON.stringify([{kind:'transaction',destination:operation.contents[1].destination,amount:'0',fee:'100000000'}]),estimates=JSON.stringify([{suggestedFeeMutez:300,gasLimit:200,storageLimit:0,burnFeeMutez:0},{suggestedFeeMutez:500,gasLimit:1500,storageLimit:0,burnFeeMutez:0}]);
const result=await api.octezConnectBuildPrepared(ops,estimates,JSON.stringify(operation));assert.equal(result.reveal.feeMutez,'999');assert.equal(result.totalDebitMutez,'1499');assert.ok(result.operations[0].opaque);assert.equal(result.operations[0].entrypoint,'default');assert.ok(result.operations[0].parameters.includes('Unit'));
const forged=await localForger.forge({branch:operation.branch,contents:operation.contents});expectedSigned=(await signer.sign(forged,new Uint8Array([3]))).sbytes;
assert.equal((await api.octezConnectExecute('https://offline.invalid',spec,result.prepared)).hash,'ooOFFLINE');assert.equal(injections,1);
console.log('PASS S03: signed/injected bytes equal the complete approved operation, including reveal fee; no re-estimation or node forging');
for(mode of ['empty','failed']){const before=injections;await assert.rejects(api.octezConnectExecute('https://offline.invalid',spec,result.prepared),/not applied/);assert.equal(injections,before);}
console.log('PASS S03: incomplete/failed preapply refused; default contract calls show unknown effects and Unit parameters');
})().catch(e=>{console.error(e);process.exitCode=1});
