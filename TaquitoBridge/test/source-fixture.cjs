const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {build} = require('esbuild');
exports.load = async function(file, substitutions = [], globals = {}, configured = () => {}) {
  let source = fs.readFileSync(path.resolve(__dirname, '../src', file), 'utf8');
  for (const [before, after] of substitutions) {
    if (!source.includes(before)) throw Error(`Fixture substitution missing: ${before}`);
    source = source.replace(before, after);
  }
  const result = await build({stdin:{contents:source,resolveDir:path.resolve(__dirname,'../src'),sourcefile:file},bundle:true,write:false,format:'iife',globalName:'API',platform:'browser',target:'safari17'});
  const context = {console:{log(){},warn(){},error(){}},Buffer,URL,Headers,Request,Response,TextEncoder,TextDecoder,setTimeout,clearTimeout,...globals};
  vm.createContext(context); vm.runInContext(result.outputFiles[0].text, context); configured(context);
  return context.API;
};
