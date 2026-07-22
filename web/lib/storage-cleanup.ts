import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

type StorageClient = Pick<SupabaseClient, 'storage'>
type QueueClient = Pick<SupabaseClient, 'from'>

type RootMatches = {
  prefixes: Set<string>
  files: Set<string>
}

export const PRIVATE_STUDENT_BUCKETS = ['result-slips', 'student-photos'] as const

const PAGE_SIZE = 100
const REMOVE_BATCH_SIZE = 100
const MAX_CLEANUP_PASSES = 3
const UUID_HEX_RE = /^[0-9a-f]{32}$/

function normalizeUuidLike(value: string): string | null {
  const unwrapped = value.startsWith('{') && value.endsWith('}')
    ? value.slice(1, -1)
    : value
  const hex = unwrapped.replaceAll('-', '').toLowerCase()
  return UUID_HEX_RE.test(hex) ? hex : null
}

function canonicalUuid(hex: string) {
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

function joinStoragePath(folder: string, name: string) {
  return folder ? `${folder}/${name}` : name
}

async function removeObjectPaths(
  supabase: StorageClient,
  bucketName: string,
  paths: string[],
): Promise<void> {
  const bucket = supabase.storage.from(bucketName)
  for (let index = 0; index < paths.length; index += REMOVE_BATCH_SIZE) {
    const { error } = await bucket.remove(paths.slice(index, index + REMOVE_BATCH_SIZE))
    if (error) throw new Error(`Could not erase ${bucketName}: ${error.message}`)
  }
}

async function removeTreePass(
  supabase: StorageClient,
  bucketName: string,
  prefix: string,
): Promise<void> {
  const bucket = supabase.storage.from(bucketName)
  const pendingFolders = [prefix]
  const visitedFolders = new Set<string>()

  while (pendingFolders.length > 0) {
    const folder = pendingFolders.pop()!
    if (visitedFolders.has(folder)) continue
    visitedFolders.add(folder)

    const files: string[] = []
    const childFolders: string[] = []
    let offset = 0

    while (true) {
      const { data: objects, error } = await bucket.list(folder, {
        limit: PAGE_SIZE,
        offset,
        sortBy: { column: 'name', order: 'asc' },
      })
      if (error) throw new Error(`Could not inspect ${bucketName}: ${error.message}`)

      for (const object of objects ?? []) {
        if (!object.name) continue
        const objectPath = joinStoragePath(folder, object.name)
        if (object.id) files.push(objectPath)
        else childFolders.push(objectPath)
      }

      if ((objects?.length ?? 0) < PAGE_SIZE) break
      offset += objects!.length
    }

    await removeObjectPaths(supabase, bucketName, files)

    pendingFolders.push(...childFolders)
  }
}

async function isPrefixEmpty(
  supabase: StorageClient,
  bucketName: string,
  prefix: string,
): Promise<boolean> {
  const { data, error } = await supabase.storage.from(bucketName).list(prefix, { limit: 1 })
  if (error) throw new Error(`Could not verify ${bucketName}: ${error.message}`)
  return (data?.length ?? 0) === 0
}

async function clearStoragePrefix(
  supabase: StorageClient,
  bucketName: string,
  prefix: string,
): Promise<void> {
  for (let pass = 0; pass < MAX_CLEANUP_PASSES; pass++) {
    await removeTreePass(supabase, bucketName, prefix)
    if (await isPrefixEmpty(supabase, bucketName, prefix)) return
  }

  throw new Error(`Could not fully erase ${bucketName}; objects are still present.`)
}

async function findEquivalentRootObjects(
  supabase: StorageClient,
  bucketName: string,
  normalizedStudentId: string,
): Promise<RootMatches> {
  const bucket = supabase.storage.from(bucketName)
  const matches: RootMatches = { prefixes: new Set(), files: new Set() }
  let offset = 0

  while (true) {
    const { data: objects, error } = await bucket.list('', {
      limit: PAGE_SIZE,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    })
    if (error) throw new Error(`Could not inspect ${bucketName}: ${error.message}`)

    for (const object of objects ?? []) {
      if (!object.name || normalizeUuidLike(object.name) !== normalizedStudentId) continue
      if (object.id) matches.files.add(object.name)
      else matches.prefixes.add(object.name)
    }

    if ((objects?.length ?? 0) < PAGE_SIZE) break
    offset += objects!.length
  }

  return matches
}

export async function removeStudentPrivateFiles(
  supabase: StorageClient,
  studentId: string,
): Promise<void> {
  const normalizedStudentId = normalizeUuidLike(studentId)
  if (!normalizedStudentId) throw new Error('Invalid student ID.')

  for (const bucketName of PRIVATE_STUDENT_BUCKETS) {
    for (let pass = 0; pass < MAX_CLEANUP_PASSES; pass++) {
      const matches = await findEquivalentRootObjects(
        supabase,
        bucketName,
        normalizedStudentId,
      )

      // The canonical path covers the normal case even if an empty virtual
      // folder is absent from the root listing. The supplied spelling covers
      // a mixed-case caller while root scanning catches every legacy spelling.
      matches.prefixes.add(canonicalUuid(normalizedStudentId))
      matches.prefixes.add(studentId)

      for (const prefix of matches.prefixes) {
        await clearStoragePrefix(supabase, bucketName, prefix)
      }
      await removeObjectPaths(supabase, bucketName, [...matches.files])

      const remaining = await findEquivalentRootObjects(
        supabase,
        bucketName,
        normalizedStudentId,
      )
      if (remaining.prefixes.size === 0 && remaining.files.size === 0) break
      if (pass === MAX_CLEANUP_PASSES - 1) {
        throw new Error(`Could not fully erase ${bucketName}; matching folders are still present.`)
      }
    }
  }
}

export async function clearPrivateStudentBuckets(supabase: StorageClient): Promise<void> {
  for (const bucketName of PRIVATE_STUDENT_BUCKETS) {
    await clearStoragePrefix(supabase, bucketName, '')
  }
}

/** Remove durable retry work only after Storage has been verified empty. If
 * this best-effort acknowledgement fails, the worker safely retries an empty
 * prefix and deletes the row later. */
export async function acknowledgeStudentStorageCleanup(
  supabase: QueueClient,
  studentId: string,
): Promise<void> {
  await supabase
    .from('student_storage_cleanup_queue')
    .delete()
    .eq('student_id', studentId)
}

export async function acknowledgeAllStudentStorageCleanup(
  supabase: QueueClient,
): Promise<void> {
  await supabase
    .from('student_storage_cleanup_queue')
    .delete()
    .not('id', 'is', null)
}
