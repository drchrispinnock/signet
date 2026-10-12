// Offline boundary regressions use production lifecycle/session bodies and substitute only SDK
// and USB dependencies. No relay or device is contacted.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const crypto = require('node:crypto');
const {build} = require('esbuild');

async function load(file, substitutions, globals) {
  let source = fs.readFileSync(path.resolve(__dirname, '../src', file), 'utf8');
  for (const [before, after] of substitutions) { assert.ok(source.includes(before)); source = source.replace(before, after); }
  const result = await build({stdin:{contents:source,resolveDir:path.resolve(__dirname,'../src'),sourcefile:file},bundle:true,write:false,format:'iife',globalName:'API',platform:'browser',target:'safari17'});
  const context = {console:{log(){},warn(){},error(){}},Buffer,URL,Headers,Request,Response,TextEncoder,TextDecoder,crypto:crypto.webcrypto,setTimeout,clearTimeout,...globals};
  vm.createContext(context);vm.runInContext(result.outputFiles[0].text,context);return context;
}

(async()=>{
  let releaseDisconnect, signalDisconnect, instances=0;
  class Wallet {
    constructor(){this.number=++instances;}
    async init(){}
    async connect(){}
    get transport(){return Promise.resolve({disconnect:async()=>{signalDisconnect();await new Promise(r=>releaseDisconnect=r);}});}
    async getPermissions(){return [{number:this.number}];}
  }
  const life = await load('octezconnect.js',[[ 'import { WalletClient } from "@tezos-x/octez.connect-wallet";', 'const WalletClient = globalThis.FakeWallet;' ]],{
    FakeWallet:Wallet,fetch:async()=>{throw Error('network prohibited');},__signet:{storageGet(){return null;},storageSet(){},storageDelete(){},octezConnectEvent(){}}
  });
  await life.API.octezConnectStart('fixture','',false);
  const disconnected = new Promise(r=>signalDisconnect=r);
  const stopping = life.API.octezConnectStop();await disconnected;
  let started=false;const starting=life.API.octezConnectStart('fixture','',false).then(x=>{started=true;return x;});
  await new Promise(r=>setTimeout(r,10));assert.equal(started,false,'start must wait for stop');
  releaseDisconnect();await stopping;await starting;
  assert.equal((await life.API.octezConnectPermissions())[0].number,2);
  assert.throws(()=>life.API.boundedJSON('['.repeat(65)+'0'+']'.repeat(65)),/structure budget/);
  assert.throws(()=>life.API.boundedJSON('x'.repeat(256*1024+1)),/parsing budget/);
  assert.deepEqual(JSON.parse(JSON.stringify(life.API.boundedJSON('{"ok":true}'))),{ok:true});
  console.log('PASS S18/S19: start waits for full disconnect; pre-parser refuses excessive size/depth');

  const apdus=[];
  class Transport {setExchangeTimeout(){} send(_cla,_ins,_p1,_p2,bytes){return this.exchange(bytes);}}
  class Signer {
    constructor(transport){this.transport=transport;}
    async publicKeyHash(){return 'fixture-account';}
    async publicKey(){return 'fixture-public-key';}
    async secretKey(){throw Error('never export');}
    async sign(label){await this.transport.send(0,0,0,0,Buffer.from(label+'0'));await this.transport.send(0,0,0,0,Buffer.from(label+'1'));return {sig:label};}
  }
  const ledger=await load('ledger.js',[
    ['import Transport from "@ledgerhq/hw-transport";','const Transport=globalThis.FakeTransport;'],
    ['import { LedgerSigner, DerivationType } from "@taquito/ledger-signer";','const LedgerSigner=globalThis.FakeSigner;const DerivationType={ED25519:0};']
  ],{FakeTransport:Transport,FakeSigner:Signer,__signet:{ledgerExchange(id,_device,hex){apdus.push(Buffer.from(hex,'hex').toString());setTimeout(()=>ledger.__signet_ledgerDone(id,'9000',null),0);}}});
  const spec={deviceId:'fixture',path:"44'/1729'/0'",address:'fixture-account'};
  const a=await ledger.API.ledgerSignerFor(spec),b=await ledger.API.ledgerSignerFor(spec);
  await Promise.all([a.sign('A'),b.sign('B')]);assert.deepEqual(apdus,['A0','A1','B0','B1']);
  console.log('PASS S22: complete Ledger signing sessions remain contiguous across concurrent signers');
  const {InMemorySigner}=require('@taquito/signer');const {b58Encode,PrefixV2}=require('@taquito/utils');
  const secret=b58Encode(new Uint8Array(32).fill(9),PrefixV2.Ed25519Seed);
  const signing=new InMemorySigner(secret);const source=await signing.publicKeyHash(),publicKey=await signing.publicKey();
  let revealFee=100;
  class Toolkit {
    constructor(){
      this.estimate={originate:async()=>({suggestedFeeMutez:500,gasLimit:1000,storageLimit:0,burnFeeMutez:0})};
      this.prepare={originate:async params=>({opOb:{branch:b58Encode(new Uint8Array(32),PrefixV2.BlockHash),protocol:'fixture',contents:[
        {kind:'reveal',source,public_key:publicKey,counter:'1',fee:String(revealFee),gas_limit:'100',storage_limit:'0'},
        {kind:'origination',source,counter:'2',fee:String(params.fee),gas_limit:String(params.gasLimit),storage_limit:String(params.storageLimit),balance:'0',script:{code:params.code,storage:params.init}}
      ]}})};
    }
    setSignerProvider(signer){this.signer=signer;}
  }
  const multisig=await load('multisig.js',[[ 'import { TezosToolkit } from "@taquito/taquito";', 'const TezosToolkit=globalThis.FakeToolkit;' ]],{
    FakeToolkit:Toolkit,fetch:async()=>{throw Error('Unexpected RPC/signing after limit mismatch');},__signet:{randomBytes:n=>[...crypto.randomBytes(n)]}
  });
  const estimate=await multisig.API.multisigEstimateOriginate('https://offline.invalid',source,publicKey,1,JSON.stringify([publicKey]));
  assert.equal(estimate.limits.revealFeeMutez,'100');assert.equal(estimate.feeMutez,'600');
  revealFee=101;
  await assert.rejects(multisig.API.multisigOriginate('https://offline.invalid',JSON.stringify({kind:'secret',secretKey:secret,address:source}),1,JSON.stringify([publicKey]),JSON.stringify(estimate.limits)),/reveal would cost more/);
  console.log('PASS S14: actual multisig origination binds its automatic reveal estimate and refuses an increased reveal before signing');

})().catch(error=>{console.error(error);process.exitCode=1;});
