// Offline regression (S04, S08, S19): a paired peer's request reaches the wallet only under the
// identity the transport proved, only with a matching grant, and only within the input budgets.
const fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const ctx={console:{log(){},warn(){},error(){},info(){},debug(){}},__signet:{randomBytes:n=>Array.from(crypto.randomBytes(n)),setTimer(){},clearTimer(){},cancelFetch(){},storageGet(){return null},storageSet(){},storageDelete(){},octezConnectEvent(){},fetch(){}}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync(require('node:path').resolve(__dirname,'../../Signet/Resources/taquito-bridge.js'),'utf8'),ctx);const api=ctx.TaquitoBridge;
const S=api.sanitizeIncomingRequest,L=api.REQUEST_LIMITS;
const peer={id:'peer-1',name:'objkt.com',publicKey:'aa'.repeat(32),relayServer:'relay.example',icon:'https://objkt.com/icon.png',appUrl:'https://objkt.com'};
const me='sender-authentic',source='tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb';
const stored={senderId:me,name:'objkt.com',icon:'https://objkt.com/icon.png',appUrl:'https://objkt.com'};
const grant=(scopes,network={type:'mainnet'})=>({senderId:me,address:source,scopes,network,accountIdentifier:'acc'});
const auth=(over={})=>({peer,senderId:me,storedMetadata:stored,permissions:[grant(['operation_request','sign'])],pendingFromPeer:0,...over});
const op={type:'operation_request',id:'r1',version:'2',senderId:me,appMetadata:{senderId:me,name:'objkt.com'},network:{type:'mainnet'},sourceAddress:source,operationDetails:[{kind:'transaction',destination:source,amount:'1'}]};

// S04: identity comes from the authenticated peer; branding from pairing or the stored grant.
let r=S({...op,senderId:'evil',appMetadata:{senderId:me,name:'Evil'}},auth());assert.ok(r.refused,'claimed sender id must be refused');
r=S({...op,appMetadata:{senderId:'evil',name:'Evil'}},auth());assert.ok(r.refused,'claimed metadata sender id must be refused');
r=S({...op,appMetadata:{name:'Totally Not Evil',icon:'https://evil.example/x.png'}},auth());assert.equal(r.refused,undefined);
assert.equal(r.request.appMetadata.name,'objkt.com');assert.equal(r.request.appMetadata.icon,'https://objkt.com/icon.png');assert.equal(r.request.senderId,me);
assert.deepEqual(Object.keys(r.request).sort(),['appMetadata','id','network','operationDetails','senderId','sourceAddress','type','version']);
r=S(op,auth({peer:null}));assert.ok(r.refused,'no paired peer');
r=S({type:'permission_request',id:'p1',version:'3',senderId:'evil',appMetadata:{senderId:'evil',name:'x'},network:{type:'mainnet'},scopes:['sign']},auth());assert.ok(r.refused,'permission under another sender id');
r=S({type:'permission_request',id:'p1',version:'3',appMetadata:{name:'Branding','senderId':me,icon:'javascript:alert(1)'},network:{type:'mainnet',rpcUrl:'ftp://x'},scopes:['sign','operation_request','bogus']},auth());
assert.equal(r.refused,undefined);assert.equal(r.request.appMetadata.senderId,me);assert.equal(r.request.appMetadata.icon,'https://objkt.com/icon.png');assert.equal(r.request.network.rpcUrl,undefined);
console.log('PASS S04: identity fields come from the authenticated peer; claimed sender ids are refused; unknown fields are stripped');

// S08: a grant for this peer, account, scope and network is required before anything is queued.
r=S(op,auth({permissions:[]}));assert.equal(r.errorType,'NOT_GRANTED_ERROR');
r=S(op,auth({permissions:[grant(['sign'])]}));assert.ok(r.refused,'operation needs operation_request scope');
r=S(op,auth({permissions:[{...grant(['operation_request']),address:'tz1other'}]}));assert.ok(r.refused,'other account');
r=S(op,auth({permissions:[{...grant(['operation_request']),senderId:'other-peer'}]}));assert.ok(r.refused,'other peer');
r=S(op,auth({permissions:[grant(['operation_request'],{type:'shadownet'})]}));assert.ok(r.refused,'other network');
r=S({...op,network:{type:'custom',rpcUrl:'https://a.example'}},auth({permissions:[grant(['operation_request'],{type:'custom',rpcUrl:'https://b.example'})]}));assert.ok(r.refused,'other custom rpc');
r=S({...op,network:{type:'custom',rpcUrl:'https://a.example'}},auth({permissions:[grant(['operation_request'],{type:'custom',rpcUrl:'https://a.example'})]}));assert.equal(r.refused,undefined);
const sign={type:'sign_payload_request',id:'s1',version:'2',senderId:me,sourceAddress:source,signingType:'micheline',payload:'0501000000076865792074657a'};
r=S(sign,auth({permissions:[grant(['operation_request'])]}));assert.ok(r.refused,'sign needs sign scope');
r=S(sign,auth());assert.equal(r.refused,undefined);assert.equal(r.request.signingType,'micheline');
console.log('PASS S08: requests without a grant for the exact peer, account, scope and network are refused');

// S19: budgets.
r=S({...op,operationDetails:Array.from({length:L.operations+1},()=>op.operationDetails[0])},auth());assert.equal(r.errorType,'TOO_MANY_OPERATIONS');
r=S({...op,operationDetails:[{kind:'transfer_ticket'}]},auth());assert.equal(r.errorType,'PARAMETERS_INVALID_ERROR');
r=S({...op,junk:'x'.repeat(L.messageChars)},auth());assert.equal(r.errorType,'PARAMETERS_INVALID_ERROR');
r=S({...sign,payload:'05'+'00'.repeat(L.payloadHex)},auth());assert.ok(r.refused,'oversized payload');
r=S(op,auth({pendingFromPeer:L.pendingPerPeer}));assert.equal(r.errorType,'ABORTED_ERROR');
r=S({...op,id:'x'.repeat(L.idChars+1)},auth());assert.ok(r.refused,'long id');
r=S('not an object',auth());assert.ok(r.refused);
r=S({...op,type:'broadcast_request'},auth());assert.ok(r.refused,'unsupported type');
console.log('PASS S19: batch size, message size, payload size, id length and per-peer pending budgets are enforced before queueing');
