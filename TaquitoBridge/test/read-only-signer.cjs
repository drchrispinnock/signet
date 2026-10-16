const assert = require('node:assert/strict');
const {load} = require('./source-fixture.cjs');
const {b58Encode,PrefixV2} = require('@taquito/utils');
(async()=>{
  const source='tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb', publicKey='fixture-public-key';
  async function contract(signer) {
    assert.equal(await signer.publicKey(),publicKey);
    assert.equal(await signer.publicKeyHash(),source);
    assert.equal(await signer.secretKey(),undefined);
    await assert.rejects(signer.sign('fixture-bytes'),error=>error.message==='read-only signer cannot sign');
  }
  const {readOnlySigner}=await load('signers.js'); await contract(readOnlySigner(publicKey,source));
  const branch=b58Encode(new Uint8Array(32),PrefixV2.BlockHash);
  const estimate={suggestedFeeMutez:100,gasLimit:100,storageLimit:0,burnFeeMutez:0};
  const operation=p=>({kind:p.kind??'transaction',source,counter:'1',fee:String(p.fee),gas_limit:String(p.gasLimit),storage_limit:String(p.storageLimit),amount:String(p.amount??0),destination:p.to??source});
  const uses=[
    ['index.js','estimateTransfer',['https://offline.invalid',source,publicKey,source,'1000']],
    ['multisig.js','multisigEstimateOriginate',['https://offline.invalid',source,publicKey,1,'["fixture-public-key"]']],
    ['octezconnect.js','octezConnectPrepare',['https://offline.invalid',source,publicKey,JSON.stringify([{kind:'transaction',destination:source,amount:'1000'}]),null]],
    ['bridge.js','estimateEtherlinkDeposit',['https://offline.invalid',source,publicKey,'KT1Wj8SUGmnEPFqyahHAcjcNQwe6YGhEXJb5','sr1'+'1'.repeat(33),source,'1000']],
  ];
  for(const [file,method,args] of uses) {
    let inspected=0;
    class Toolkit {
      constructor(){
        const estimated=async()=>{await contract(this.signer);inspected++;return estimate;};
        const prepared=async p=>({opOb:{branch,protocol:'fixture',contents:[operation(p)]}});
        this.estimate={transfer:estimated,originate:estimated,batch:async()=>[await estimated()]};
        this.prepare={transaction:prepared,originate:prepared,batch:async params=>({opOb:{branch,protocol:'fixture',contents:params.map(operation)}})};
      }
      setSignerProvider(signer){this.signer=signer;}
    }
    const api=await load(file, [['import { TezosToolkit } from "@taquito/taquito";','const TezosToolkit=globalThis.FixtureToolkit;']],{
      FixtureToolkit:Toolkit,fetch:async()=>{throw Error('network prohibited');},__signet:{},
    });
    const result=await api[method](...args);
    assert.equal(inspected,1,`${file} must estimate with the shared signer`);
    assert.equal(result.feeMutez??result.totalFeeMutez,'100');
  }
  console.log('PASS F15: identity, no secret, exact refusal and successful transfer/multisig/dApp/bridge estimates');
})().catch(error=>{console.error(error);process.exitCode=1;});
