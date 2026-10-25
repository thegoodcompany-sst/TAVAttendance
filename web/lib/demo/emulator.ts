/* eslint-disable @typescript-eslint/no-explicit-any */
/**
 * A small in-memory stand-in for the subset of supabase-js that TAVA uses:
 * PostgREST-style `.from()` queries (filters, embeds, ordering, mutations),
 * the app's RPCs, `auth`, and `storage`. It never performs network I/O, so a
 * demo session cannot read from or write to the real database.
 */
import { emptyJournal, recordChange, canPersistJournal, type DemoJournal } from './journal'
import { validDemoTables } from './journal-validation'
import { DEMO_USER_ID, DEMO_EMAIL } from './constants'
import { STUDY_SPACE_CLASS_ID, sgDate, type DemoRow, type DemoTables } from './seed'

export type DemoError = { message: string; code?: string; details?: string | null; hint?: string | null }
export type DemoResult<T = any> = { data: T; error: DemoError | null; count: number | null; status: number; statusText: string }

/** Foreign keys used for resource embedding: [childTable, column, parentTable]. */
const FOREIGN_KEYS: Array<[string, string, string]> = [
  ['attendance_records', 'session_id', 'sessions'],
  ['attendance_records', 'student_id', 'students'],
  ['sessions', 'class_id', 'classes'],
  ['enrollments', 'student_id', 'students'],
  ['enrollments', 'class_id', 'classes'],
  ['messages', 'student_id', 'students'],
  ['awards', 'student_id', 'students'],
  ['correction_requests', 'student_id', 'students'],
  ['result_slips', 'student_id', 'students'],
  ['student_results', 'student_id', 'students'],
  ['parent_student_links', 'student_id', 'students'],
  ['parent_student_links', 'parent_id', 'profiles'],
  ['class_tutor_assignments', 'class_id', 'classes'],
  ['class_tutor_assignments', 'tutor_id', 'profiles'],
  ['consent_records', 'student_id', 'students'],
  ['dismissals', 'student_id', 'students'],
  ['dismissals', 'session_id', 'sessions'],
]

/** Columns filled in by the "server" when a row is inserted. */
function insertDefaults(table: string, now: string): Record<string, unknown> {
  switch (table) {
    case 'attendance_records': return { marked_at: now, notes: null, late_reason: null, absence_informed: null }
    case 'messages': return { sent_at: now, read_at: null }
    case 'awards': return { awarded_at: now }
    case 'result_slips': return { uploaded_at: now, acknowledged_at: null }
    case 'students': return { is_active: true, avatar_url: null, created_at: now }
    case 'classes': return { is_active: true, is_study_space: false, created_at: now }
    case 'enrollments': return { is_active: true, enrolled_at: now }
    case 'sessions': return { created_at: now, started_at: null, ended_at: null, notes: null }
    case 'profiles': return { created_at: now }
    default: return { created_at: now }
  }
}

/** Fires for every successful demo mutation (used to persist the journal). */
export type DemoChange = { table: string; upserted: DemoRow[]; deleted: string[] }

export type DemoDatabase = {
  tables: DemoTables
  /** Wall clock used for server-assigned timestamps. */
  now: () => number
  journal?: DemoJournal
  onChange?: (change: DemoChange) => void
}

const ok = <T>(data: T, count: number | null = null, status = 200): DemoResult<T> =>
  ({ data, error: null, count, status, statusText: 'OK' })
const fail = (message: string, code = 'DEMO', status = 400): DemoResult<null> =>
  ({ data: null, error: { message, code, details: null, hint: null }, count: null, status, statusText: 'Error' })

/** Stage the entire operation, including multi-table RPCs, before publishing it. */
function transact(db: DemoDatabase, run: () => DemoResult): DemoResult {
  const tables = db.tables
  const onChange = db.onChange
  const changes: DemoChange[] = []
  db.tables = structuredClone(tables)
  db.onChange = change => changes.push(structuredClone(change))
  let candidate: DemoTables
  let journal: DemoJournal
  let result: DemoResult
  try {
    result = run()
    if (result.error || !changes.length) return result
    journal = structuredClone(db.journal ?? emptyJournal())
    for (const change of changes) recordChange(journal, change)
    if (!validDemoTables(db.tables) || !canPersistJournal(journal)) {
      return fail('Demo persistence limit exceeded or invalid data. Your previous changes have been kept.')
    }
    candidate = db.tables
  } finally {
    db.tables = tables
    db.onChange = onChange
  }
  db.tables = candidate
  db.journal = journal
  for (const change of changes) onChange?.(change)
  return result
}

function newId(): string {
  return globalThis.crypto.randomUUID()
}

// ── Select parsing ─────────────────────────────────────────────────────────

type SelectNode = {
  columns: string[] | '*'
  embeds: EmbedNode[]
}
type EmbedNode = {
  alias: string
  table: string
  inner: boolean
  select: SelectNode
}

function splitTopLevel(input: string, separator = ','): string[] {
  const parts: string[] = []
  let depth = 0
  let current = ''
  for (const ch of input) {
    if (ch === '(') depth++
    if (ch === ')') depth--
    if (ch === separator && depth === 0) {
      parts.push(current)
      current = ''
    } else {
      current += ch
    }
  }
  if (current.trim()) parts.push(current)
  return parts.map(p => p.trim()).filter(Boolean)
}

export function parseSelect(select: string | undefined): SelectNode {
  const source = (select ?? '*').replace(/\s+/g, ' ').trim() || '*'
  const node: SelectNode = { columns: [], embeds: [] }
  for (const part of splitTopLevel(source)) {
    const open = part.indexOf('(')
    if (open >= 0 && part.endsWith(')')) {
      const head = part.slice(0, open).trim()
      const inside = part.slice(open + 1, -1)
      const [aliasPart, tablePart] = head.includes(':') ? head.split(':') : [head, head]
      const [table, ...hints] = tablePart.trim().split('!')
      node.embeds.push({
        alias: aliasPart.trim(),
        table: table.trim(),
        inner: hints.includes('inner'),
        select: parseSelect(inside),
      })
    } else if (part === '*') {
      node.columns = '*'
    } else if (node.columns !== '*') {
      // `alias:column` and casts (`col::text`) are reduced to the column name.
      const name = part.includes(':') && !part.includes('::') ? part.split(':')[1] : part.split('::')[0]
      node.columns.push(name.trim())
    }
  }
  if (Array.isArray(node.columns) && node.columns.length === 0 && node.embeds.length === 0) node.columns = '*'
  return node
}

// ── Filters ────────────────────────────────────────────────────────────────

type Filter = { path: string[]; op: string; value: unknown; negate?: boolean }
type OrGroup = { kind: 'or' | 'and'; items: Array<Filter | OrGroup> }

function compare(a: unknown, b: unknown): number {
  if (a === b) return 0
  if (a === null || a === undefined) return 1
  if (b === null || b === undefined) return -1
  if (typeof a === 'number' && typeof b === 'number') return a - b
  if (typeof a === 'boolean' || typeof b === 'boolean') return String(a).localeCompare(String(b))
  const na = Number(a)
  const nb = Number(b)
  if (typeof a !== 'string' || typeof b !== 'string') {
    if (!Number.isNaN(na) && !Number.isNaN(nb)) return na - nb
  }
  return String(a) < String(b) ? -1 : String(a) > String(b) ? 1 : 0
}

function coerce(raw: string): unknown {
  if (raw === 'null') return null
  if (raw === 'true') return true
  if (raw === 'false') return false
  return raw
}

function loose(a: unknown, b: unknown): boolean {
  if (a === b) return true
  if (a === null || a === undefined || b === null || b === undefined) return false
  return String(a) === String(b)
}

function testValue(cell: unknown, op: string, value: unknown): boolean {
  switch (op) {
    case 'eq': return loose(cell, value)
    case 'neq': return !loose(cell, value)
    case 'gt': return cell !== null && cell !== undefined && compare(cell, value) > 0
    case 'gte': return cell !== null && cell !== undefined && compare(cell, value) >= 0
    case 'lt': return cell !== null && cell !== undefined && compare(cell, value) < 0
    case 'lte': return cell !== null && cell !== undefined && compare(cell, value) <= 0
    case 'in': return (value as unknown[]).some(v => loose(cell, v))
    case 'is': return value === null ? cell === null || cell === undefined : cell === value
    case 'like':
    case 'ilike': {
      const pattern = String(value).replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*').replace(/_/g, '.')
      return new RegExp(`^${pattern}$`, op === 'ilike' ? 'i' : '').test(String(cell ?? ''))
    }
    default: return true
  }
}

function parseLogic(expr: string): OrGroup['items'] {
  return splitTopLevel(expr).map(part => {
    const logic = part.match(/^(and|or)\((.*)\)$/)
    if (logic) return { kind: logic[1] as 'and' | 'or', items: parseLogic(logic[2]) }
    const [column, ...rest] = part.split('.')
    let op = rest.shift() ?? 'eq'
    let negate = false
    if (op === 'not') {
      negate = true
      op = rest.shift() ?? 'eq'
    }
    const rawValue = rest.join('.')
    const value = op === 'in'
      ? rawValue.replace(/^\(|\)$/g, '').split(',').map(v => coerce(v.trim().replace(/^"|"$/g, '')))
      : coerce(rawValue)
    return { path: [column], op, value, negate }
  })
}

function getPath(row: any, path: string[]): unknown {
  let cur = row
  for (const key of path) {
    if (cur === null || cur === undefined) return undefined
    cur = cur[key]
  }
  return cur
}

function evalLogic(row: DemoRow, node: Filter | OrGroup): boolean {
  if ('kind' in node) {
    return node.kind === 'or' ? node.items.some(item => evalLogic(row, item)) : node.items.every(item => evalLogic(row, item))
  }
  const result = testValue(getPath(row, node.path), node.op, node.value)
  return node.negate ? !result : result
}

// ── Query builder ──────────────────────────────────────────────────────────

type Mode = 'select' | 'insert' | 'update' | 'upsert' | 'delete'

class DemoQuery implements PromiseLike<DemoResult> {
  private mode: Mode = 'select'
  private selectText: string | undefined = '*'
  private returning = false
  private filters: Filter[] = []
  private logic: OrGroup[] = []
  private orders: Array<{ path: string[]; ascending: boolean; nullsFirst: boolean }> = []
  private limitN: number | null = null
  private rangeFrom: number | null = null
  private rangeTo: number | null = null
  private singleMode: 'single' | 'maybe' | null = null
  private payload: Record<string, unknown>[] = []
  private onConflict: string[] = []
  private ignoreDuplicates = false
  private countMode: string | null = null
  private head = false

  constructor(private readonly db: DemoDatabase, private readonly table: string) {}

  select(columns?: string, options?: { count?: string; head?: boolean }) {
    if (this.mode === 'select') {
      this.selectText = columns ?? '*'
    } else {
      this.returning = true
      this.selectText = columns ?? '*'
    }
    if (options?.count) this.countMode = options.count
    if (options?.head) this.head = true
    return this
  }

  insert(values: Record<string, unknown> | Record<string, unknown>[]) {
    this.mode = 'insert'
    this.payload = Array.isArray(values) ? values : [values]
    return this
  }

  upsert(values: Record<string, unknown> | Record<string, unknown>[], options?: { onConflict?: string; ignoreDuplicates?: boolean }) {
    this.mode = 'upsert'
    this.payload = Array.isArray(values) ? values : [values]
    this.onConflict = (options?.onConflict ?? 'id').split(',').map(s => s.trim())
    this.ignoreDuplicates = options?.ignoreDuplicates ?? false
    return this
  }

  update(values: Record<string, unknown>) {
    this.mode = 'update'
    this.payload = [values]
    return this
  }

  delete() {
    this.mode = 'delete'
    return this
  }

  private add(column: string, op: string, value: unknown, negate = false) {
    this.filters.push({ path: column.split('.'), op, value, negate })
    return this
  }

  eq(column: string, value: unknown) { return this.add(column, 'eq', value) }
  neq(column: string, value: unknown) { return this.add(column, 'neq', value) }
  gt(column: string, value: unknown) { return this.add(column, 'gt', value) }
  gte(column: string, value: unknown) { return this.add(column, 'gte', value) }
  lt(column: string, value: unknown) { return this.add(column, 'lt', value) }
  lte(column: string, value: unknown) { return this.add(column, 'lte', value) }
  like(column: string, value: unknown) { return this.add(column, 'like', value) }
  ilike(column: string, value: unknown) { return this.add(column, 'ilike', value) }
  is(column: string, value: unknown) { return this.add(column, 'is', value) }
  in(column: string, values: readonly unknown[]) { return this.add(column, 'in', [...values]) }
  not(column: string, op: string, value: unknown) {
    const parsed = op === 'in' && typeof value === 'string'
      ? value.replace(/^\(|\)$/g, '').split(',').map(v => coerce(v.trim()))
      : op === 'is' && value === 'null' ? null : value
    return this.add(column, op, parsed, true)
  }
  match(query: Record<string, unknown>) {
    for (const [k, v] of Object.entries(query)) this.add(k, 'eq', v)
    return this
  }
  filter(column: string, op: string, value: unknown) {
    if (op.startsWith('not.')) return this.add(column, op.slice(4), value, true)
    return this.add(column, op, value)
  }
  or(expression: string) {
    this.logic.push({ kind: 'or', items: parseLogic(expression) })
    return this
  }
  order(column: string, options?: { ascending?: boolean; nullsFirst?: boolean; referencedTable?: string; foreignTable?: string }) {
    const ascending = options?.ascending ?? true
    this.orders.push({ path: column.split('.'), ascending, nullsFirst: options?.nullsFirst ?? !ascending })
    return this
  }
  limit(n: number) { this.limitN = n; return this }
  range(from: number, to: number) { this.rangeFrom = from; this.rangeTo = to; return this }
  single() { this.singleMode = 'single'; return this }
  maybeSingle() { this.singleMode = 'maybe'; return this }
  abortSignal() { return this }
  returns() { return this }
  throwOnError() { return this }

  then<TResult1 = DemoResult, TResult2 = never>(
    onfulfilled?: ((value: DemoResult) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null,
  ): PromiseLike<TResult1 | TResult2> {
    let result: DemoResult
    try {
      result = this.mode === 'select' ? this.execute() : transact(this.db, () => this.execute())
    } catch (error) {
      result = fail(error instanceof Error ? error.message : 'Demo query failed')
    }
    return Promise.resolve(result).then(onfulfilled, onrejected)
  }

  private rows(): DemoRow[] {
    return readTable(this.db, this.table)
  }

  private ownFilters(): Filter[] {
    return this.filters.filter(f => f.path.length === 1)
  }

  private matchesOwn(row: DemoRow): boolean {
    return this.ownFilters().every(f => {
      const r = testValue(row[f.path[0]], f.op, f.value)
      return f.negate ? !r : r
    }) && this.logic.every(group => evalLogic(row, group))
  }

  private execute(): DemoResult {
    switch (this.mode) {
      case 'select': return this.runSelect(this.rows().filter(r => this.matchesOwn(r)))
      case 'insert': return this.runInsert(false)
      case 'upsert': return this.runInsert(true)
      case 'update': return this.runUpdate()
      case 'delete': return this.runDelete()
    }
  }

  private shape(rows: DemoRow[]): DemoResult {
    const node = parseSelect(this.selectText)
    const budget = { rows: 5000, scans: 100000, bytes: 1024 * 1024 }
    let out = rows
      .map(row => project(this.db, this.table, row, node, this.filters.filter(f => f.path.length > 1), budget))
      .filter((r): r is Record<string, unknown> => r !== null)

    for (const order of [...this.orders].reverse()) {
      out = [...out].sort((a, b) => {
        const av = getPath(a, order.path) ?? getPath(rowsById(rows, a), order.path)
        const bv = getPath(b, order.path) ?? getPath(rowsById(rows, b), order.path)
        const aNull = av === null || av === undefined
        const bNull = bv === null || bv === undefined
        if (aNull || bNull) {
          if (aNull && bNull) return 0
          return aNull === order.nullsFirst ? -1 : 1
        }
        const c = compare(av, bv)
        return order.ascending ? c : -c
      })
    }
    const count = out.length
    if (this.rangeFrom !== null && this.rangeTo !== null) out = out.slice(this.rangeFrom, this.rangeTo + 1)
    if (this.limitN !== null) out = out.slice(0, this.limitN)
    if (this.head) return ok(null, count)
    if (this.singleMode) {
      if (out.length === 1) return ok(out[0], this.countMode ? count : null)
      if (out.length === 0 && this.singleMode === 'maybe') return ok(null, this.countMode ? 0 : null)
      return { ...fail('JSON object requested, multiple (or no) rows returned', 'PGRST116', 406) }
    }
    return ok(out, this.countMode ? count : null)
  }

  private runSelect(rows: DemoRow[]): DemoResult {
    return this.shape(rows)
  }

  private runInsert(upsert: boolean): DemoResult {
    const nowIso = new Date(this.db.now()).toISOString()
    const table = mutableTable(this.db, this.table)
    const written: DemoRow[] = []
    for (const values of this.payload) {
      if (upsert) {
        const existing = table.find(row => this.onConflict.every(col => loose(row[col], values[col])))
        if (existing) {
          if (!this.ignoreDuplicates) Object.assign(existing, values)
          written.push(existing)
          continue
        }
      }
      const row = { ...insertDefaults(this.table, nowIso), id: newId(), ...values } as DemoRow
      if (this.table === 'messages' || this.table === 'result_slips' || this.table === 'awards') {
        if (row.sender_id === undefined && this.table === 'messages') row.sender_id = DEMO_USER_ID
      }
      table.push(row)
      written.push(row)
    }
    this.db.onChange?.({ table: this.table, upserted: written, deleted: [] })
    if (!this.returning) return ok(null, null, 201)
    return this.shape(written)
  }

  private runUpdate(): DemoResult {
    const table = mutableTable(this.db, this.table)
    const matched = table.filter(row => this.matchesOwn(row))
    for (const row of matched) Object.assign(row, this.payload[0])
    if (matched.length) this.db.onChange?.({ table: this.table, upserted: matched, deleted: [] })
    if (!this.returning) return ok(null, null, 204)
    return this.shape(matched)
  }

  private runDelete(): DemoResult {
    const table = mutableTable(this.db, this.table)
    const matched = table.filter(row => this.matchesOwn(row))
    const ids = new Set(matched.map(r => r.id))
    this.db.tables[this.table] = table.filter(row => !ids.has(row.id))
    if (matched.length) this.db.onChange?.({ table: this.table, upserted: [], deleted: [...ids] })
    if (!this.returning) return ok(null, null, 204)
    return this.shape(matched)
  }
}

function rowsById(rows: DemoRow[], shaped: Record<string, unknown>): DemoRow | undefined {
  return shaped && typeof shaped.id === 'string' ? rows.find(r => r.id === shaped.id) : undefined
}

function mutableTable(db: DemoDatabase, table: string): DemoRow[] {
  if (VIEWS[table]) throw new Error(`${table} is read-only in demo mode`)
  db.tables[table] ??= []
  return db.tables[table]
}

type ProjectionBudget = { rows: number; scans: number; bytes: number }

function spend(budget: ProjectionBudget, kind: keyof ProjectionBudget, amount: number) {
  budget[kind] -= amount
  if (budget[kind] < 0) throw new Error('Demo query expansion limit exceeded; reset the demo to continue.')
}

/** Projects one row through a select tree. Returns null if an !inner embed or nested filter excludes it. */
function project(db: DemoDatabase, table: string, row: DemoRow, node: SelectNode, nested: Filter[], budget: ProjectionBudget): Record<string, unknown> | null {
  spend(budget, 'rows', 1)
  const out: Record<string, unknown> = {}
  if (node.columns === '*') Object.assign(out, row)
  else for (const col of node.columns) out[col] = row[col] ?? null

  spend(budget, 'bytes', Buffer.byteLength(JSON.stringify(out), 'utf8'))

  for (const embed of node.embeds) {
    const childFilters = nested
      .filter(f => f.path[0] === embed.alias || f.path[0] === embed.table)
      .map(f => ({ ...f, path: f.path.slice(1) }))
    const own = childFilters.filter(f => f.path.length === 1)
    const deeper = childFilters.filter(f => f.path.length > 1)
    const passes = (child: DemoRow) => own.every(f => {
      const r = testValue(child[f.path[0]], f.op, f.value)
      return f.negate ? !r : r
    })

    const toOne = FOREIGN_KEYS.find(([child, , parent]) => child === table && parent === embed.table)
    if (toOne) {
      const [, column] = toOne
      const parentRow = readTable(db, embed.table).find(r => {
        spend(budget, 'scans', 1)
        return r.id === row[column]
      })
      const value = parentRow && passes(parentRow) ? project(db, embed.table, parentRow, embed.select, deeper, budget) : null
      if (!value && embed.inner) return null
      if (!value && own.length > 0 && !embed.inner) {
        out[embed.alias] = null
        continue
      }
      out[embed.alias] = value
      continue
    }
    const toMany = FOREIGN_KEYS.find(([child, , parent]) => child === embed.table && parent === table)
    if (toMany) {
      const [, column] = toMany
      const children = readTable(db, embed.table)
        .filter(r => {
          spend(budget, 'scans', 1)
          return r[column] === row.id && passes(r)
        })
        .map(r => project(db, embed.table, r, embed.select, deeper, budget))
        .filter((r): r is Record<string, unknown> => r !== null)
      if (embed.inner && children.length === 0) return null
      out[embed.alias] = children
      continue
    }
    throw new Error(`Could not find a relationship between '${table}' and '${embed.table}' (demo)`)
  }
  return out
}

// ── Views ──────────────────────────────────────────────────────────────────

const VIEWS: Record<string, (db: DemoDatabase) => DemoRow[]> = {
  attendance_summary: db => {
    const classes = new Map(readTable(db, 'classes').map(c => [c.id, c]))
    const students = new Map(readTable(db, 'students').map(s => [s.id, s]))
    const sessions = new Map(readTable(db, 'sessions').map(s => [s.id, s]))
    const agg = new Map<string, DemoRow>()
    for (const r of readTable(db, 'attendance_records')) {
      const session = sessions.get(r.session_id as string)
      const cls = session && classes.get(session.class_id as string)
      const student = students.get(r.student_id as string)
      if (!session || !cls || !student) continue
      if (cls.is_study_space || !cls.is_active || !student.is_active) continue
      const key = `${student.id}:${cls.id}`
      const row = agg.get(key) ?? {
        id: key, student_id: student.id, student_name: student.full_name, class_id: cls.id, class_name: cls.name,
        total_sessions: 0, present_count: 0, late_count: 0, absent_count: 0, attendance_pct: null,
      }
      row.total_sessions = (row.total_sessions as number) + 1
      const field = `${r.status}_count`
      row[field] = ((row[field] as number) ?? 0) + 1
      agg.set(key, row)
    }
    for (const row of agg.values()) {
      const total = row.total_sessions as number
      row.attendance_pct = total ? Math.round((((row.present_count as number) + (row.late_count as number)) / total) * 1000) / 10 : null
    }
    return [...agg.values()]
  },
  current_consent: db => {
    const latest = new Map<string, DemoRow>()
    for (const r of readTable(db, 'consent_records')) {
      const key = `${r.student_id}:${r.consent_type}`
      const prev = latest.get(key)
      if (!prev || String(r.created_at) >= String(prev.created_at)) latest.set(key, r)
    }
    return [...latest.values()]
  },
  app_events_daily: () => [],
}

function readTable(db: DemoDatabase, table: string): DemoRow[] {
  const view = VIEWS[table]
  if (view) return view(db)
  return db.tables[table] ?? []
}

// ── RPCs ───────────────────────────────────────────────────────────────────

type RpcHandler = (db: DemoDatabase, args: Record<string, any>) => DemoResult

/** Explicit opt-in: new RPCs (including get-or-create handlers) stage writes by default. */
const READ_ONLY_RPCS = new Set([
  'get_my_classes',
  'get_session_roster',
  'get_retrospective_session_roster',
  'get_study_space_roster',
  'get_roster_for_date',
  'export_student_personal_data',
  'get_student_nfc_binding',
  'class_punctuality',
  'get_parent_children',
  'get_parent_messages',
  'get_parent_result_slips',
  'get_parent_attendance_summary',
  'get_parent_attendance_history',
  'get_parent_dismissals',
  'is_superadmin',
])

function today(db: DemoDatabase): string {
  return sgDate(db.now())
}

function change(db: DemoDatabase, table: string, upserted: DemoRow[], deleted: string[] = []) {
  db.onChange?.({ table, upserted, deleted })
}

function rosterFor(db: DemoDatabase, sessionId: string): DemoRow[] | null {
  const session = readTable(db, 'sessions').find(s => s.id === sessionId)
  if (!session) return null
  const enrolled = new Set(readTable(db, 'enrollments').filter(e => e.class_id === session.class_id && e.is_active).map(e => e.student_id))
  const records = readTable(db, 'attendance_records').filter(r => r.session_id === sessionId)
  return readTable(db, 'students')
    .filter(s => s.is_active && (enrolled.has(s.id) || records.some(r => r.student_id === s.id)))
    .sort((a, b) => String(a.full_name).localeCompare(String(b.full_name)))
    .map(s => {
      const r = records.find(rec => rec.student_id === s.id)
      return {
        id: s.id,
        student_id: s.id,
        full_name: s.full_name,
        attendance_id: r?.id ?? null,
        status: r?.status ?? null,
        marked_at: r?.marked_at ?? null,
        notes: r?.notes ?? null,
        late_reason: r?.late_reason ?? null,
        absence_informed: r?.absence_informed ?? null,
        avatar_url: s.avatar_url ?? null,
      }
    })
}

function getOrCreateSession(db: DemoDatabase, classId: string): DemoRow {
  const date = today(db)
  const sessions = mutableTable(db, 'sessions')
  const existing = sessions.find(s => s.class_id === classId && s.session_date === date)
  if (existing) return existing
  const row: DemoRow = {
    id: newId(), class_id: classId, session_date: date, topic: null, notes: null,
    started_at: null, ended_at: null, sub_tutor_id: null, created_at: new Date(db.now()).toISOString(),
  }
  sessions.push(row)
  change(db, 'sessions', [row])
  return row
}

const RPCS: Record<string, RpcHandler> = {
  get_my_classes: db => ok(
    readTable(db, 'classes')
      .filter(c => c.is_active && !c.is_study_space)
      .sort((a, b) => String(a.name).localeCompare(String(b.name)))
      .map(c => ({ ...c, can_manage_sessions: true, can_operate_today_session: true })),
  ),
  get_or_create_today_session: (db, a) => {
    if (!readTable(db, 'classes').some(c => c.id === a.p_class_id)) return fail('class not found')
    return ok(getOrCreateSession(db, a.p_class_id))
  },
  get_session_roster: (db, a) => {
    const roster = rosterFor(db, a.p_session_id)
    return roster ? ok(roster) : fail('session not found')
  },
  get_retrospective_session_roster: (db, a) => {
    const roster = rosterFor(db, a.session_id)
    return roster ? ok(roster) : fail('session not found')
  },
  get_study_space_roster: (db, a) => {
    const records = readTable(db, 'attendance_records').filter(r => r.session_id === a.p_session_id)
    return ok(readTable(db, 'students').filter(s => s.is_active).map(s => {
      const r = records.find(rec => rec.student_id === s.id)
      return { student_id: s.id, full_name: s.full_name, attendance_id: r?.id ?? null, status: r?.status ?? null, marked_at: r?.marked_at ?? null, avatar_url: null }
    }))
  },
  get_roster_for_date: (db, a) => {
    const classes = new Map(readTable(db, 'classes').map(c => [c.id, c]))
    const sessions = readTable(db, 'sessions').filter(s => s.session_date === a.p_date && !classes.get(s.class_id as string)?.is_study_space)
    const rank: Record<string, number> = { late: 3, present: 2, absent: 1 }
    const merged = new Map<string, DemoRow>()
    for (const session of sessions) {
      for (const r of rosterFor(db, session.id as string) ?? []) {
        const className = String(classes.get(session.class_id as string)?.name ?? 'Class')
        const prev = merged.get(r.student_id as string)
        if (!prev) {
          merged.set(r.student_id as string, { id: r.student_id as string, student_id: r.student_id, full_name: r.full_name, class_names: [className], status: r.status, marked_at: r.marked_at })
        } else {
          (prev.class_names as string[]).push(className)
          if (r.status && (!prev.status || rank[r.status as string] > rank[prev.status as string])) prev.status = r.status
          if (r.marked_at && (!prev.marked_at || String(r.marked_at) > String(prev.marked_at))) prev.marked_at = r.marked_at
        }
      }
    }
    return ok([...merged.values()].sort((x, y) => String(x.full_name).localeCompare(String(y.full_name))))
  },
  set_session_lifecycle: (db, a) => {
    const session = mutableTable(db, 'sessions').find(s => s.id === a.p_session_id)
    if (!session) return fail('session not found')
    const nowIso = new Date(db.now()).toISOString()
    if (a.p_action === 'start') session.started_at ??= nowIso
    else if (a.p_action === 'end') session.ended_at = nowIso
    else return fail('unknown action')
    change(db, 'sessions', [session])
    return ok(session)
  },
  update_session_note: (db, a) => {
    const session = mutableTable(db, 'sessions').find(s => s.id === a.p_session_id)
    if (!session) return fail('session not found')
    session.notes = a.p_notes ?? null
    change(db, 'sessions', [session])
    return ok(null)
  },
  clear_attendance: (db, a) => {
    const table = mutableTable(db, 'attendance_records')
    const removed = table.filter(r => r.session_id === a.p_session_id && r.student_id === a.p_student_id).map(r => r.id)
    db.tables.attendance_records = table.filter(r => !removed.includes(r.id))
    change(db, 'attendance_records', [], removed)
    return ok(null)
  },
  create_student_with_consent: (db, a) => {
    const nowIso = new Date(db.now()).toISOString()
    const student: DemoRow = {
      id: newId(), full_name: a.p_full_name, school: a.p_school ?? null, year_of_study: a.p_year_of_study ?? null,
      notes: a.p_notes ?? null, date_of_birth: a.p_date_of_birth ?? null, is_active: true, avatar_url: null, created_at: nowIso,
    }
    mutableTable(db, 'students').push(student)
    const consent: DemoRow = {
      id: newId(), student_id: student.id, consent_type: 'data_collection', status: 'granted', method: 'admin_attested',
      notice_version: '1.1', granted_by: DEMO_USER_ID, parent_id: null, source_note: a.p_source_note ?? null, created_at: nowIso,
    }
    mutableTable(db, 'consent_records').push(consent)
    change(db, 'students', [student])
    change(db, 'consent_records', [consent])
    return ok(student)
  },
  record_admin_consent: (db, a) => {
    const consent: DemoRow = {
      id: newId(), student_id: a.p_student_id, consent_type: a.p_consent_type, status: a.p_status, method: 'admin_attested',
      notice_version: '1.1', granted_by: DEMO_USER_ID, parent_id: null, source_note: a.p_source_note ?? null,
      created_at: new Date(db.now()).toISOString(),
    }
    mutableTable(db, 'consent_records').push(consent)
    change(db, 'consent_records', [consent])
    return ok(null)
  },
  review_correction_request: (db, a) => {
    const request = mutableTable(db, 'correction_requests').find(r => r.id === a.p_request_id)
    if (!request) return fail('correction request not found')
    request.status = a.p_decision
    request.reviewed_by = DEMO_USER_ID
    request.reviewed_at = new Date(db.now()).toISOString()
    request.review_note = a.p_review_note ?? null
    change(db, 'correction_requests', [request])
    if (a.p_decision === 'applied') {
      const student = mutableTable(db, 'students').find(s => s.id === request.student_id)
      if (student && typeof request.field_name === 'string') {
        student[request.field_name] = request.requested_value
        change(db, 'students', [student])
      }
    }
    return ok(request.student_id)
  },
  export_student_personal_data: (db, a) => {
    const student = readTable(db, 'students').find(s => s.id === a.p_student_id)
    if (!student) return fail('student not found')
    return ok({
      student,
      enrollments: readTable(db, 'enrollments').filter(e => e.student_id === student.id),
      attendance: readTable(db, 'attendance_records').filter(r => r.student_id === student.id),
      consent: readTable(db, 'consent_records').filter(r => r.student_id === student.id),
    })
  },
  anonymise_student_secure: (db, a) => {
    const student = mutableTable(db, 'students').find(s => s.id === a.p_student_id)
    if (!student) return fail('student not found')
    Object.assign(student, { full_name: 'Pseudonymised student', school: null, notes: null, date_of_birth: null, is_active: false })
    change(db, 'students', [student])
    return ok(null)
  },
  erase_student_secure: (db, a) => {
    const id = a.p_student_id
    for (const table of ['attendance_records', 'enrollments', 'consent_records', 'student_results', 'result_slips', 'messages', 'parent_student_links']) {
      const removed = (db.tables[table] ?? []).filter(r => r.student_id === id).map(r => r.id)
      if (removed.length) {
        db.tables[table] = (db.tables[table] ?? []).filter(r => r.student_id !== id)
        change(db, table, [], removed)
      }
    }
    db.tables.students = (db.tables.students ?? []).filter(s => s.id !== id)
    change(db, 'students', [], [id])
    return ok(null)
  },
  link_parent_student: (db, a) => {
    const links = mutableTable(db, 'parent_student_links')
    if (!links.some(l => l.parent_id === a.p_parent && l.student_id === a.p_student)) {
      const row: DemoRow = { id: newId(), parent_id: a.p_parent, student_id: a.p_student }
      links.push(row)
      change(db, 'parent_student_links', [row])
    }
    return ok(null)
  },
  unlink_parent_student: (db, a) => {
    const links = mutableTable(db, 'parent_student_links')
    const removed = links.filter(l => l.parent_id === a.p_parent && l.student_id === a.p_student).map(l => l.id)
    db.tables.parent_student_links = links.filter(l => !removed.includes(l.id))
    change(db, 'parent_student_links', [], removed)
    return ok(null)
  },
  get_student_nfc_binding: (db, a) => {
    const binding = readTable(db, 'nfc_chip_bindings').find(b => b.student_id === a.p_student_id && !b.revoked_at)
    return ok(binding ? { chip_uid_suffix: binding.chip_uid_suffix, issued_at: binding.issued_at } : null)
  },
  pair_nfc_chip: (db, a) => {
    const uid = String(a.p_chip_uid ?? '')
    const bindings = mutableTable(db, 'nfc_chip_bindings')
    const nowIso = new Date(db.now()).toISOString()
    const revoked: DemoRow[] = []
    for (const b of bindings) {
      if (!b.revoked_at && (b.student_id === a.p_student_id || b.chip_uid === uid)) {
        b.revoked_at = nowIso
        revoked.push(b)
      }
    }
    const row: DemoRow = { id: newId(), student_id: a.p_student_id, chip_uid: uid, chip_uid_suffix: uid.slice(-4), issued_at: nowIso, revoked_at: null }
    bindings.push(row)
    change(db, 'nfc_chip_bindings', [...revoked, row])
    return ok({ chip_uid_suffix: row.chip_uid_suffix, issued_at: nowIso })
  },
  revoke_nfc_chip_for_student: (db, a) => {
    const nowIso = new Date(db.now()).toISOString()
    const revoked = mutableTable(db, 'nfc_chip_bindings').filter(b => b.student_id === a.p_student_id && !b.revoked_at)
    for (const b of revoked) b.revoked_at = nowIso
    change(db, 'nfc_chip_bindings', revoked)
    return ok(null)
  },
  class_punctuality: (db, a) => {
    const sessionIds = new Set(readTable(db, 'sessions')
      .filter(s => s.class_id === a.p_class_id && String(s.session_date) >= a.p_from && String(s.session_date) <= a.p_to)
      .map(s => s.id))
    const rows = readTable(db, 'attendance_records').filter(r => sessionIds.has(r.session_id as string))
    const present = rows.filter(r => r.status === 'present').length
    const late = rows.filter(r => r.status === 'late').length
    const absent = rows.filter(r => r.status === 'absent').length
    return ok([{ present_count: present, late_count: late, absent_count: absent, total_count: rows.length, on_time_rate: present + late ? present / (present + late) : null }])
  },
  get_parent_children: () => ok([]),
  get_parent_messages: (db, a) => ok(readTable(db, 'messages').filter(m => m.student_id === a.p_student_id)),
  get_parent_result_slips: (db, a) => ok(readTable(db, 'result_slips').filter(r => r.student_id === a.p_student_id)),
  get_parent_attendance_summary: () => ok([]),
  get_parent_attendance_history: () => ok([]),
  get_parent_dismissals: () => ok([]),
  send_parent_message: (db, a) => {
    const row: DemoRow = { id: newId(), sender_id: DEMO_USER_ID, recipient_id: null, student_id: a.p_student_id, subject: a.p_subject ?? null, body: a.p_body, sent_at: new Date(db.now()).toISOString(), read_at: null }
    mutableTable(db, 'messages').push(row)
    change(db, 'messages', [row])
    return ok([{ ...row, is_from_parent: true }])
  },
  is_superadmin: () => ok(false),
  consume_invite_rate_limit: () => ok(true),
  submit_app_events: () => ok(0),
  reserve_result_slip_upload: () => fail('File uploads are switched off in demo mode.'),
  finalize_result_slip_upload: () => fail('File uploads are switched off in demo mode.'),
  wipe_operational_data_secure: () => fail('Wiping data is switched off in demo mode.'),
}

// ── Client ─────────────────────────────────────────────────────────────────

const demoUser = {
  id: DEMO_USER_ID,
  email: DEMO_EMAIL,
  aud: 'authenticated',
  role: 'authenticated',
  app_metadata: { provider: 'demo' },
  user_metadata: { full_name: 'Demo Admin' },
  created_at: new Date(0).toISOString(),
}

const storageStub = {
  from: () => ({
    upload: async () => fail('File uploads are switched off in demo mode.'),
    download: async () => fail('Files are not available in demo mode.'),
    list: async () => ok([]),
    remove: async () => ok([]),
    createSignedUrl: async () => fail('Files are not available in demo mode.'),
    createSignedUrls: async () => ok([]),
    createSignedUploadUrl: async () => fail('File uploads are switched off in demo mode.'),
    getPublicUrl: () => ({ data: { publicUrl: '' } }),
  }),
}

export function createDemoClient(db: DemoDatabase) {
  return {
    __demo: true as const,
    from: (table: string) => new DemoQuery(db, table),
    rpc: (fn: string, args: Record<string, any> = {}) => {
      const handler = RPCS[fn]
      const run = (): DemoResult => {
        if (!handler) return fail(`${fn} is not available in demo mode.`)
        try {
          // Detach only the response so callers cannot mutate stored rows through it.
          if (READ_ONLY_RPCS.has(fn)) return structuredClone(handler(db, args))
          return transact(db, () => handler(db, args))
        } catch (error) {
          return fail(error instanceof Error ? error.message : `${fn} failed in demo mode`)
        }
      }
      // supabase-js RPC builders are thenable and allow chained modifiers.
      const builder: any = {
        then: (resolve: any, reject: any) => Promise.resolve(run()).then(resolve, reject),
        single: () => builder,
        maybeSingle: () => builder,
        select: () => builder,
        order: () => builder,
        limit: () => builder,
        eq: () => builder,
        abortSignal: () => builder,
        returns: () => builder,
        throwOnError: () => builder,
      }
      return builder
    },
    auth: {
      getUser: async () => ({ data: { user: demoUser }, error: null }),
      getClaims: async () => ({ data: { claims: { sub: DEMO_USER_ID, email: DEMO_EMAIL, role: 'authenticated' } }, error: null }),
      getSession: async () => ({ data: { session: null }, error: null }),
      signOut: async () => ({ error: null }),
      signInWithPassword: async () => ({ data: { user: demoUser, session: null }, error: null }),
      setSession: async () => ({ data: { user: demoUser, session: null }, error: null }),
      updateUser: async () => ({ data: { user: demoUser }, error: { message: 'Not available in demo mode.' } }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
      admin: {
        inviteUserByEmail: async (email: string, options?: { data?: Record<string, unknown> }) => {
          const user = { id: newId(), email }
          const profile: DemoRow = {
            id: user.id,
            full_name: String(options?.data?.full_name ?? email.split('@')[0]),
            role: String(options?.data?.role ?? 'tutor'),
            phone: null,
            created_at: new Date(db.now()).toISOString(),
          }
          return transact(db, () => {
            mutableTable(db, 'profiles').push(profile)
            change(db, 'profiles', [profile])
            return ok({ user })
          })
        },
        deleteUser: async (userId: string) => {
          return transact(db, () => {
            db.tables.profiles = (db.tables.profiles ?? []).filter(p => p.id !== userId)
            change(db, 'profiles', [], [userId])
            return ok({})
          })
        },
      },
    },
    storage: storageStub,
    channel: () => ({ on: () => ({ subscribe: () => ({}) }), subscribe: () => ({}) }),
    removeChannel: async () => 'ok',
  }
}

export type DemoClient = ReturnType<typeof createDemoClient>

/** Today's date helper exported for tests. */
export const demoToday = today
export { STUDY_SPACE_CLASS_ID }
