#!/usr/bin/env node
// Advisor watch (research-frontier Tier 2 #7): fetch the Supabase security +
// performance advisors and FAIL when a finding appears that is not in the
// accepted list (scripts/advisor-accepted.json). The accepted list is the
// reviewed baseline — every key in it was deliberately accepted (rationale in
// HUMANS.md Notes); anything new is a regression to surface.
//
// Live:    SUPABASE_ACCESS_TOKEN=... node scripts/advisor-watch.mjs
// Offline: node scripts/advisor-watch.mjs dump.json [more.json ...]
//          where each file is an advisor API/MCP response: {"lints":[...]}
//          (or wrapped as {"result":{"lints":[...]}}).
// Re-baseline after a human review: add --accept to fold current findings in.

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const PROJECT_REF = 'zgikcbsxzjgbigywxbbj'
const ACCEPTED_PATH = join(dirname(fileURLToPath(import.meta.url)), 'advisor-accepted.json')

const args = process.argv.slice(2)
const accept = args.includes('--accept')
const files = args.filter((a) => a !== '--accept')

function extractLints(parsed) {
  const lints = parsed?.lints ?? parsed?.result?.lints
  if (!Array.isArray(lints)) throw new Error('no "lints" array found in input')
  return lints
}

async function fetchLints() {
  const token = process.env.SUPABASE_ACCESS_TOKEN
  if (!token) {
    console.error('Set SUPABASE_ACCESS_TOKEN, or pass advisor dump file(s).')
    process.exit(2)
  }
  const all = []
  for (const type of ['security', 'performance']) {
    const res = await fetch(
      `https://api.supabase.com/v1/projects/${PROJECT_REF}/advisors/${type}`,
      { headers: { Authorization: `Bearer ${token}` } },
    )
    if (!res.ok) throw new Error(`advisors/${type}: HTTP ${res.status} ${await res.text()}`)
    all.push(...extractLints(await res.json()))
  }
  return all
}

const lints = files.length > 0
  ? files.flatMap((f) => extractLints(JSON.parse(readFileSync(f, 'utf8'))))
  : await fetchLints()

const acceptedDoc = JSON.parse(readFileSync(ACCEPTED_PATH, 'utf8'))
const accepted = new Set(acceptedDoc.accepted)

const fresh = lints.filter((l) => !accepted.has(l.cache_key))
const seen = new Set(lints.map((l) => l.cache_key))
const stale = acceptedDoc.accepted.filter((k) => !seen.has(k))

if (stale.length > 0) {
  console.log(`${stale.length} accepted finding(s) no longer reported (resolved — prune when convenient):`)
  for (const k of stale) console.log(`  - ${k}`)
}

if (accept) {
  acceptedDoc.generated = new Date().toISOString().slice(0, 10)
  acceptedDoc.accepted = [...seen].sort()
  writeFileSync(ACCEPTED_PATH, JSON.stringify(acceptedDoc, null, 2) + '\n')
  console.log(`Baseline rewritten: ${acceptedDoc.accepted.length} accepted finding(s).`)
  process.exit(0)
}

if (fresh.length === 0) {
  console.log(`No new advisor findings (${lints.length} known, all accepted).`)
  process.exit(0)
}

console.error(`\n${fresh.length} NEW advisor finding(s) not in the accepted baseline:\n`)
for (const l of fresh) {
  console.error(`[${l.level}] ${l.title}`)
  console.error(`  ${l.detail ?? l.description}`)
  console.error(`  ${l.remediation}`)
  console.error(`  cache_key: ${l.cache_key}\n`)
}
console.error('Fix the finding, or (after human review) re-baseline with --accept.')
process.exit(1)
