// Source-only, conservative reachability check. Acorn owns JavaScript syntax and the complete
// module inventory; unsupported linkage is an error, never an implicitly read-only export.
const {parse} = require('acorn');
const path = require('node:path');
const roots = new Set(['signerFor', 'injectSigned', 'signAndInject', 'sendApproved', 'ledgerSignerFor']);
function walk(node, visit, parent, key) {
  if (!node || typeof node.type !== 'string') return;
  visit(node, parent, key);
  for (const [k, value] of Object.entries(node)) {
    if (Array.isArray(value)) value.forEach(child => walk(child, visit, node, k));
    else if (value && typeof value === 'object') walk(value, visit, node, k);
  }
}
function scan(files) {
  const modules = new Map();
  const id = (file, name) => `${file}:${name}`;
  function localFile(file, source) {
    if (!source.startsWith('.')) return null;
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(file), source));
    if (target.endsWith('.json')) return null;
    if (!Object.hasOwn(files, target)) throw Error(`Missing module ${target}`);
    return target;
  }
  for (const [file, source] of Object.entries(files)) {
    const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
    const mod = {defs: new Map(), imports: new Map(), exports: new Map(), stars: [], ast};
    modules.set(file, mod);
    function declaration(node) {
      if (node.type === 'VariableDeclaration') {
        for (const d of node.declarations) {
          if (d.id.type !== 'Identifier') throw Error(`${file}: destructured module bindings unsupported`);
          mod.defs.set(d.id.name, {nodes: [d.init], class: false});
        }
        return node.declarations.map(d => d.id.name);
      }
      if (['FunctionDeclaration', 'ClassDeclaration'].includes(node.type) && node.id) {
        mod.defs.set(node.id.name, {nodes: [node], class: node.type === 'ClassDeclaration'});
        return [node.id.name];
      }
      throw Error(`${file}: unsupported declaration ${node.type}`);
    }
    for (const node of ast.body) {
      switch (node.type) {
        case 'ImportDeclaration': {
          const target = localFile(file, node.source.value);
          for (const s of node.specifiers) {
            if (target && s.type !== 'ImportSpecifier') throw Error(`${file}: local default/namespace import unsupported`);
            mod.imports.set(s.local.name, {file: target, name: s.imported?.name ?? s.local.name});
          }
          break;
        }
        case 'ExportDefaultDeclaration': throw Error(`${file}: default export unsupported`);
        case 'ExportAllDeclaration': {
          const target = localFile(file, node.source.value);
          if (!target || node.exported) throw Error(`${file}: namespace/external re-export unsupported`);
          mod.stars.push(target); break;
        }
        case 'ExportNamedDeclaration': {
          if (node.declaration) {
            for (const name of declaration(node.declaration)) mod.exports.set(name, {file, name});
          } else {
            const target = node.source ? localFile(file, node.source.value) : file;
            if (!target) throw Error(`${file}: external re-export unsupported`);
            for (const s of node.specifiers) {
              if (s.local.type !== 'Identifier' || s.exported.type !== 'Identifier') throw Error(`${file}: string export unsupported`);
              mod.exports.set(s.exported.name, {file: target, name: s.local.name});
            }
          }
          break;
        }
        case 'VariableDeclaration': case 'FunctionDeclaration': case 'ClassDeclaration': declaration(node); break;
        default: break; // Module setup is visited below too (including later assignments).
      }
    }
    walk(ast, node => {
      if (node.type === 'VariableDeclaration' && node.kind === 'var') throw Error(`${file}: hoisted var bindings unsupported`);
      if (node.type === 'ImportExpression' || (['CallExpression', 'NewExpression'].includes(node.type) && node.callee.type === 'Identifier' && ['eval', 'Function'].includes(node.callee.name))) {
        throw Error(`${file}: dynamic code/linkage unsupported`);
      }
      if (node.type === 'AssignmentExpression') {
        let left = node.left;
        while (left.type === 'MemberExpression') left = left.object;
        if (left.type === 'Identifier' && mod.defs.has(left.name)) mod.defs.get(left.name).nodes.push(node.right);
      }
    });
  }
  function surface(file, visiting = new Set()) {
    const mod = modules.get(file);
    if (!mod) throw Error(`Missing module ${file}`);
    if (visiting.has(file)) throw Error(`Cyclic star exports: ${file}`);
    const next = new Set([...visiting, file]);
    const result = new Map(mod.exports);
    for (const target of mod.stars) for (const [name, binding] of surface(target, next)) {
      if (result.has(name) && !mod.exports.has(name)) throw Error(`Ambiguous star export ${name}`);
      if (!mod.exports.has(name)) result.set(name, binding);
    }
    return result;
  }
  function resolve(file, name, seen = new Set()) {
    const key = id(file, name);
    if (seen.has(key)) throw Error(`Cyclic alias ${key}`);
    seen = new Set([...seen, key]);
    const mod = modules.get(file);
    if (mod.defs.has(name)) return key;
    const imported = mod.imports.get(name);
    if (imported) {
      if (!imported.file) return `external:${imported.name}`;
      const binding = surface(imported.file).get(imported.name);
      if (!binding) throw Error(`Unknown import ${key}`);
      return resolve(binding.file, binding.name, seen);
    }
    const binding = surface(file).get(name);
    if (!binding || (binding.file === file && binding.name === name)) throw Error(`Unknown export ${key}`);
    return resolve(binding.file, binding.name, seen);
  }
  const graph = new Map(), signing = new Set(['external:LedgerSigner', ...[...roots].map(name => `external:${name}`)]);
  for (const [file, mod] of modules) {
    // Resolve every local import/export, even if it is currently unreachable from index.js.
    for (const name of mod.imports.keys()) resolve(file, name);
    for (const binding of surface(file).values()) resolve(binding.file, binding.name);
    for (const [name, def] of mod.defs) {
      const key = id(file, name), refs = new Set();
      if (roots.has(name)) signing.add(key);
      for (const node of def.nodes) walk(node, (n, parent, role) => {
        if (n.type !== 'Identifier') return;
        if (parent?.type === 'MemberExpression' && role === 'property' && !parent.computed) return;
        if (['Property', 'MethodDefinition', 'PropertyDefinition'].includes(parent?.type) && role === 'key' && !parent.computed && !parent.shorthand) return;
        if (mod.defs.has(n.name) || mod.imports.has(n.name)) refs.add(resolve(file, n.name));
        else if (roots.has(n.name)) signing.add(key);
        // A fixture or future module may construct the global LedgerSigner directly.
        if (n.name === 'LedgerSigner' && parent?.type === 'NewExpression' && role === 'callee') signing.add(key);
      });
      graph.set(key, refs);
    }
  }
  let grew;
  do {
    grew = false;
    for (const [key, refs] of graph) if (!signing.has(key) && [...refs].some(ref => signing.has(ref))) { signing.add(key); grew = true; }
  } while (grew);
  const exported = surface('index.js'), signed = [];
  for (const [name, binding] of exported) {
    const key = resolve(binding.file, binding.name);
    for (const [file, mod] of modules) for (const [local, def] of mod.defs) {
      if (id(file, local) === key && def.class) throw Error(`Class on public surface: ${name}`);
    }
    if (signing.has(key)) signed.push(name);
  }
  return {surface: [...exported.keys()].sort(), signing: signed.sort()};
}
module.exports = {scan};
