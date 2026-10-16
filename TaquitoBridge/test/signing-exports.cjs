const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {scan} = require('./signing-scan.cjs');
const root = 'export async function signerFor(spec) { return spec; }';
const imported = 'import { signerFor } from "./signers.js";';
// F18: each of the five counterexamples previously returned no signing export without error.
const cases = [
  `${imported}\n  export async function danger(s) { return signerFor(s); }`,
  `${imported}\nfunction helper(s) { return signerFor(s); } export function danger(s) { return helper(s); }`,
  `${imported}\nexport const danger = (s) =>\n signerFor(s);`,
  `${imported}\n  function helper(s) { return signerFor(s); }\nexport function danger(s) { return helper(s); }`,
  'export function danger(t) { return new LedgerSigner (t); }',
  `${imported}\nexport const danger = signerFor;`,
  `${imported}\nconst box = { send: signerFor }; export function danger(s) { return box.send(s); }`,
  `${imported}\nlet helper; helper = signerFor; export function danger(s) { return helper(s); }`,
  imported + '\nexport function danger(s) { return `${signerFor(s)}`; }',
];
for (const source of cases) assert.deepEqual(scan({'index.js': source, 'signers.js': root}).signing, ['danger']);
const mixed = scan({
  'index.js': `${imported}\nexport { viaAlias as danger } from './ops.js'; export * from './star.js';
    export function viaForTest(s) { return signerFor(s); }
    export function readOnly(x) { return /signerFor\\(/.test(x) + 'signerFor(s)'; }
    export const dotted = x => x.signerFor(1);`,
  'ops.js': `${imported}\nconst helper = s => signerFor(s); export const viaAlias = helper;`,
  'signers.js': root,
  'star.js': 'export function starSigner(s) { return injectSigned(s); } function injectSigned(s) { return s; } export const read = 1;',
});
assert.deepEqual(mixed.signing, ['danger', 'starSigner', 'viaForTest']);
assert.deepEqual(mixed.surface, ['danger', 'dotted', 'read', 'readOnly', 'starSigner', 'viaForTest']);
for (const files of [
  {'index.js':'export default function(s) { return s; }'},
  {'index.js':'export function broken() {'},
  {'index.js':'export * from "./missing.js";'},
  {'index.js':'export {nothing} from "./other.js";', 'other.js':'export const read = 1;'},
  {'index.js':'export class Thing {}'},
  {'index.js':`${imported} export const {danger} = signerFor;`, 'signers.js':root},
  {'index.js':'export const danger = () => eval("signerFor()");'},
  {'index.js':'export const danger = () => import("./hidden.js");'},
  {'index.js':'import * as ops from "./ops.js"; export const danger = () => ops.send();', 'ops.js':root},
  {'index.js':`${imported} if(true) {var hidden = signerFor;} export const danger = () => hidden();`, 'signers.js':root},
  {'ops.js':root},
]) assert.throws(() => scan(files));
const dir = path.resolve(__dirname, '../src');
const files = Object.fromEntries(fs.readdirSync(dir).filter(f => f.endsWith('.js')).map(f => [f, fs.readFileSync(path.join(dir, f), 'utf8')]));
const actual = scan(files);
const swift = fs.readFileSync(path.resolve(__dirname, '../../Signet/Services/TaquitoBridge.swift'), 'utf8');
const declaration = swift.match(/static let signingCalls: Set<String> = \[([^\]]+)\]/);
assert.ok(declaration, 'native signing policy must be found');
const declared = [...declaration[1].matchAll(/"([^"]+)"/g)].map(m => m[1]).filter(n => n !== 'ledgerAppVersion').sort();
assert.deepEqual(actual.signing, declared, 'every signing export must match the native policy exactly');
// esbuild independently inventories the entry module's public exports, including re-exports.
const {buildSync} = require('esbuild');
const built = buildSync({entryPoints:[path.join(dir,'index.js')],bundle:true,write:false,metafile:true,format:'esm',platform:'browser',logLevel:'silent'});
const inventory = Object.values(built.metafile.outputs).flatMap(o => o.exports).sort();
assert.deepEqual(actual.surface, inventory, 'scan must account for the complete real export inventory');
// Prove a newly added unprotected export is detected by the production-source check.
const mutation = {...files, 'index.js': files['index.js'] + '\n  export const unprotectedAuditFixture = s =>\n    signerFor(s);\n'};
assert.ok(scan(mutation).signing.includes('unprotectedAuditFixture'));
assert.notDeepEqual(scan(mutation).signing, declared);
console.log('PASS F18: syntax-based signing reachability, fail-closed fixtures, complete export inventory and unprotected-export mutation');
