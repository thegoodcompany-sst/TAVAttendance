#!/usr/bin/env node
// Fails when web/ code references a table, column, or RPC that prod's schema lacks
// (the 2026-06-27 outage class: code deployed before its migration).
//
// Usage: node scripts/check-web-schema.mjs <schema.json>
//   schema.json: {"tables": [...], "columns": [...], "routines": [...]} for the
//   public schema. Produce it with scripts/drift-check.sh (psql) or via the
//   Supabase MCP query documented there.
//
// ponytail: column names are checked against the whole public schema, not
// per-table — catches "column exists nowhere" (the real outage) with zero
// maintenance; upgrade to per-table matching if a wrong-table bug ever slips.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const schemaPath = process.argv[2];
if (!schemaPath) {
  console.error('usage: node scripts/check-web-schema.mjs <schema.json>');
  process.exit(2);
}
const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));
const tables = new Set(schema.tables);
const columns = new Set(schema.columns);
const routines = new Set(schema.routines);
const known = new Set([...tables, ...columns]);

function* sourceFiles(dir) {
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name === '.next') continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) yield* sourceFiles(p);
    else if (/\.(ts|tsx)$/.test(name)) yield p;
  }
}

const failures = [];
const check = (set, ident, file, what) => {
  if (!set.has(ident)) failures.push(`${file}: ${what} "${ident}" not found in prod schema`);
};

for (const file of sourceFiles(join(root, 'web'))) {
  const src = readFileSync(file, 'utf8');
  const rel = file.slice(root.length + 1);

  for (const m of src.matchAll(/\.from\(\s*['"`](\w+)['"`]/g))
    check(tables, m[1], rel, 'table/view');
  for (const m of src.matchAll(/\.rpc\(\s*['"`](\w+)['"`]/g))
    check(routines, m[1], rel, 'function');
  // first string arg of filter/order builders is a (possibly alias-dotted) column path
  for (const m of src.matchAll(/\.(?:eq|neq|gt|gte|lt|lte|like|ilike|is|in|contains|not|order)\(\s*['"`]([\w.]+)['"`]/g))
    check(columns, m[1].split('.').pop(), rel, 'column');
  // select strings: "alias:relation!hint(cols)" — validate relation names and columns
  for (const m of src.matchAll(/\.select\(\s*(['"`])([\s\S]*?)\1/g)) {
    for (let token of m[2].split(/[\s,()]+/)) {
      if (!token || token === '*') continue;
      if (token.includes(':')) token = token.split(':').pop();
      token = token.split('!')[0];
      if (/^\w+$/.test(token)) check(known, token, rel, 'identifier');
    }
  }
}

if (failures.length) {
  console.error('Schema check FAILED — deploying this would 400 against prod:');
  for (const f of failures) console.error('  ' + f);
  process.exit(1);
}
console.log('Schema check passed: all web schema references exist in prod.');
