/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import {
  auditDetail,
  auditEntityLabel,
  parseAuditCursor,
} from '@/lib/queries/activity-helpers'

export type AuditLogEntry = {
  id: string
  tableName: string
  recordId: string
  action: 'INSERT' | 'UPDATE' | 'DELETE'
  oldData: Record<string, unknown> | null
  newData: Record<string, unknown> | null
  changedBy: string | null
  changedAt: string
  actorName: string
  actorRole: string | null
  verb: string
  entityLabel: string
  detail: string
}

const AUDIT_VERB = { INSERT: 'created', UPDATE: 'edited', DELETE: 'deleted' } as const

export async function getAuditLog({
  user,
  table,
  limit = 50,
  before,
}: {
  user?: string
  table?: string
  limit?: number
  before?: string
} = {}): Promise<AuditLogEntry[]> {
  const supabase = await createClient()
  let query = supabase
    .from('audit_log')
    .select('id, table_name, record_id, action, old_data, new_data, changed_by, changed_at')
    .order('changed_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 100))

  if (user) query = query.eq('changed_by', user)
  if (table) query = query.eq('table_name', table)
  // Timestamp + UUID only; reject characters that could break PostgREST `.or()` filters.
  const cursor = parseAuditCursor(before)
  if (cursor) {
    query = query.or(
      `changed_at.lt.${cursor.beforeAt},and(changed_at.eq.${cursor.beforeAt},id.lt.${cursor.beforeId})`,
    )
  }

  const { data, error } = await query
  if (error) throw new Error(`getAuditLog: ${error.message}`)

  const actorIds = [...new Set((data ?? []).map((row: any) => row.changed_by).filter(Boolean))]
  const actors = new Map<string, { fullName: string; role: string }>()
  if (actorIds.length > 0) {
    const { data: profiles, error: profilesError } = await supabase
      .from('profiles')
      .select('id, full_name, role')
      .in('id', actorIds)
    if (profilesError) throw new Error(`getAuditLog profiles: ${profilesError.message}`)
    for (const profile of profiles ?? []) {
      actors.set(profile.id, { fullName: profile.full_name, role: profile.role })
    }
  }

  const classIds = new Set<string>()
  const studentIds = new Set<string>()
  for (const row of data ?? []) {
    const snap = (row.new_data ?? row.old_data ?? {}) as Record<string, any>
    if (row.table_name === 'sessions' || row.table_name === 'enrollments') {
      if (snap.class_id) classIds.add(snap.class_id)
    }
    if (row.table_name === 'enrollments' || row.table_name === 'attendance_records') {
      if (snap.student_id) studentIds.add(snap.student_id)
    }
  }

  const classNames = new Map<string, string>()
  const studentNames = new Map<string, string>()
  if (classIds.size > 0) {
    const { data: classes } = await supabase.from('classes').select('id, name').in('id', [...classIds])
    for (const c of classes ?? []) classNames.set(c.id, c.name)
  }
  if (studentIds.size > 0) {
    const { data: students } = await supabase.from('students').select('id, full_name').in('id', [...studentIds])
    for (const s of students ?? []) studentNames.set(s.id, s.full_name)
  }

  return (data ?? []).map((row: any) => {
    const actor = row.changed_by ? actors.get(row.changed_by) : null
    return {
      id: row.id,
      tableName: row.table_name,
      recordId: row.record_id,
      action: row.action,
      oldData: row.old_data,
      newData: row.new_data,
      changedBy: row.changed_by,
      changedAt: row.changed_at,
      actorName: actor?.fullName ?? 'System',
      actorRole: actor?.role ?? null,
      verb: AUDIT_VERB[row.action as keyof typeof AUDIT_VERB] ?? 'changed',
      entityLabel: auditEntityLabel(row, classNames, studentNames),
      detail: auditDetail(row),
    }
  })
}

export type AuditActor = { id: string; fullName: string; role: string }

export const getAuditActors = cache(async (): Promise<AuditActor[]> => {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, role')
    .order('full_name')
  if (error) throw new Error(`getAuditActors: ${error.message}`)
  return (data ?? []).map((profile: any) => ({
    id: profile.id,
    fullName: profile.full_name,
    role: profile.role,
  }))
})

export type RecentAppEvent = {
  id: string
  occurredAt: string
  platform: 'ios' | 'android' | 'web'
  eventType: 'screen_view' | 'tap' | 'error' | 'crash' | 'ops' | 'latency'
  name: string
  role: string | null
  properties: Record<string, unknown>
}

export async function getRecentEvents({
  platform,
  type,
  limit = 50,
}: {
  platform?: string
  type?: string
  limit?: number
} = {}): Promise<RecentAppEvent[]> {
  const supabase = await createClient()
  let query = supabase
    .from('app_events')
    .select('id, occurred_at, platform, event_type, name, role, properties')
    .order('occurred_at', { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 100))

  if (platform && ['ios', 'android', 'web'].includes(platform)) query = query.eq('platform', platform)
  if (type && ['screen_view', 'tap', 'error', 'crash', 'ops', 'latency'].includes(type)) query = query.eq('event_type', type)

  const { data, error } = await query
  if (error) throw new Error(`getRecentEvents: ${error.message}`)
  return (data ?? []).map((row: any) => ({
    id: row.id,
    occurredAt: row.occurred_at,
    platform: row.platform,
    eventType: row.event_type,
    name: row.name,
    role: row.role,
    properties: row.properties ?? {},
  }))
}

