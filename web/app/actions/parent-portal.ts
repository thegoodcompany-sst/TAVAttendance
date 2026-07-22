'use server'

import { revalidatePath } from 'next/cache'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { createAdminClient } from '@/lib/supabase/admin'
import { createClient } from '@/lib/supabase/server'

const ALLOWED_TYPES = new Set(['application/pdf', 'image/jpeg', 'image/png'])
const MAX_BYTES = 10 * 1024 * 1024
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const OBJECT_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$/

type ResultSlipUpload = {
  path: string
  fileType: string
  fileSize: number
  examName: string
  subject: string | null
  score: number | null
  maxScore: number | null
}

type PreparedUpload = {
  path: string | null
  token: string | null
  error: string | null
}

function isCanonicalStudentPath(studentId: string, path: string) {
  if (!UUID_RE.test(studentId) || studentId !== studentId.toLowerCase()) return false
  const [folder, objectName, ...extra] = path.split('/')
  return extra.length === 0 && folder === studentId && OBJECT_NAME_RE.test(objectName ?? '')
}

function safeObjectName(fileName: string) {
  return fileName.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 200) || 'upload'
}

async function parentOwnsStudent(
  supabase: Awaited<ReturnType<typeof createClient>>,
  studentId: string,
) {
  const { data: children, error } = await supabase.rpc('get_parent_children')
  const childRows = (children ?? []) as Array<{ id: string }>
  return !error && childRows.some(child => child.id === studentId)
}

export async function prepareResultSlipUpload(
  studentId: string,
  fileName: string,
  fileType: string,
  fileSize: number,
): Promise<PreparedUpload> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { path: null, token: null, error: 'Not authenticated.' }
  if (!(await isFeatureEnabled('parent_portal'))) {
    return { path: null, token: null, error: 'Parent portal is not enabled.' }
  }
  if (!(await parentOwnsStudent(supabase, studentId))) {
    return { path: null, token: null, error: 'Not authorized.' }
  }
  if (!ALLOWED_TYPES.has(fileType)) {
    return { path: null, token: null, error: 'File must be a PDF, JPG, or PNG.' }
  }
  if (!Number.isSafeInteger(fileSize) || fileSize <= 0 || fileSize > MAX_BYTES) {
    return { path: null, token: null, error: 'File must be non-empty and under 10MB.' }
  }

  const path = `${studentId}/${crypto.randomUUID()}-${safeObjectName(fileName)}`
  const adminClient = createAdminClient()
  const { error: reserveError } = await adminClient.rpc('reserve_result_slip_upload', {
    p_actor_id: user.id,
    p_student_id: studentId,
    p_path: path,
    p_expected_size: fileSize,
    p_expected_mime: fileType,
  })
  if (reserveError) {
    return { path: null, token: null, error: 'Upload limit reached or upload is not authorized.' }
  }

  const { data, error } = await adminClient.storage
    .from('result-slips')
    .createSignedUploadUrl(path)
  if (error || !data?.token) {
    await adminClient.from('result_slip_upload_intents').delete().eq('path', path)
    return { path: null, token: null, error: 'Could not prepare the upload.' }
  }

  return { path, token: data.token, error: null }
}

async function fileSignatureMatches(file: Blob, mime: string) {
  const bytes = new Uint8Array(await file.slice(0, 1024).arrayBuffer())
  if (mime === 'image/png') {
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    return signature.every((value, index) => bytes[index] === value)
  }
  if (mime === 'image/jpeg') {
    return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
  }
  if (mime === 'application/pdf') {
    return new TextDecoder('ascii').decode(bytes.slice(0, 5)) === '%PDF-'
  }
  return false
}

/**
 * Finalise a browser-to-Supabase upload. The browser sends the object directly
 * to Storage; this action then downloads it through the trusted service client
 * for metadata and signature validation before atomically consuming its intent.
 */
export async function finalizeResultSlipUpload(
  studentId: string,
  upload: ResultSlipUpload,
): Promise<{ error: string | null }> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }
  if (!(await isFeatureEnabled('parent_portal'))) {
    return { error: 'Parent portal is not enabled.' }
  }
  if (!(await parentOwnsStudent(supabase, studentId))) {
    return { error: 'Not authorized.' }
  }

  const examName = upload.examName.trim()
  const subject = upload.subject?.trim() || null
  const { score, maxScore } = upload

  if (!examName) return { error: 'Exam name is required.' }
  if (examName.length > 200) return { error: 'Exam name must be 200 characters or fewer.' }
  if (subject && subject.length > 100) return { error: 'Subject must be 100 characters or fewer.' }
  if (!isCanonicalStudentPath(studentId, upload.path)) return { error: 'Invalid upload path.' }
  if (!Number.isSafeInteger(upload.fileSize) || upload.fileSize <= 0) {
    return { error: 'A non-empty file is required.' }
  }
  if (!ALLOWED_TYPES.has(upload.fileType)) return { error: 'File must be a PDF, JPG, or PNG.' }
  if (upload.fileSize > MAX_BYTES) return { error: 'File must be under 10MB.' }
  if (score !== null && (!Number.isFinite(score) || score < 0)) return { error: 'Score must be zero or greater.' }
  if (maxScore !== null && (!Number.isFinite(maxScore) || maxScore <= 0)) return { error: 'Maximum score must be greater than zero.' }
  if (score !== null && maxScore !== null && score > maxScore) return { error: 'Score cannot exceed the maximum.' }

  // Do not trust client-supplied size/type metadata. The Storage service has
  // already enforced the bucket limits; this existence/metadata check also
  // prevents creating database rows for files that were never uploaded.
  const adminClient = createAdminClient()
  const { data: intent, error: intentError } = await adminClient
    .from('result_slip_upload_intents')
    .select('student_id, actor_id, expected_size, expected_mime, expires_at')
    .eq('path', upload.path)
    .eq('student_id', studentId)
    .eq('actor_id', user.id)
    .is('cleanup_claimed_at', null)
    .maybeSingle()
  if (
    intentError || !intent || new Date(intent.expires_at).getTime() <= Date.now() ||
    intent.expected_size !== upload.fileSize || intent.expected_mime !== upload.fileType
  ) {
    return { error: 'Upload authorization is invalid or expired.' }
  }

  const objectName = upload.path.slice(studentId.length + 1)
  const { data: objects, error: listError } = await adminClient.storage
    .from('result-slips')
    .list(studentId, { limit: 100, search: objectName })
  if (listError) return { error: 'Could not verify the uploaded file.' }
  const object = objects?.find(candidate => candidate.id && candidate.name === objectName)
  const metadata = object?.metadata as Record<string, unknown> | undefined
  const storedSize = typeof metadata?.size === 'number' ? metadata.size : null
  const storedType = typeof metadata?.mimetype === 'string' ? metadata.mimetype : null
  if (!object || storedSize !== upload.fileSize || storedType !== upload.fileType) {
    await adminClient.storage.from('result-slips').remove([upload.path])
    // Keep the path tombstone until the signed token expires. The client
    // already holds that token and could otherwise recreate an untracked file.
    return { error: 'Uploaded file verification failed.' }
  }

  const { data: storedFile, error: downloadError } = await adminClient.storage
    .from('result-slips')
    .download(upload.path)
  if (downloadError || !storedFile || !(await fileSignatureMatches(storedFile, upload.fileType))) {
    await adminClient.storage.from('result-slips').remove([upload.path])
    // A rejected upload token remains reusable until expiry; retaining the
    // intent lets the cleanup worker remove any late replay at the exact path.
    return { error: 'The file contents do not match the selected file type.' }
  }

  const { error } = await adminClient.rpc('finalize_result_slip_upload', {
    p_actor_id: user.id,
    p_student_id: studentId,
    p_path: upload.path,
    p_exam_name: examName,
    p_subject: subject,
    p_score: score,
    p_max_score: maxScore,
  })
  if (error) {
    // The database may have committed even if the HTTP response was lost.
    // Resolve that ambiguous state before reporting failure, and never delete
    // an object here: a live intent supports a retry, while the expiry worker
    // safely removes genuinely abandoned uploads later.
    const { data: persisted } = await adminClient
      .from('result_slips')
      .select('id')
      .eq('student_id', studentId)
      .eq('uploaded_by', user.id)
      .eq('file_path', upload.path)
      .limit(1)
      .maybeSingle()
    if (persisted) {
      revalidatePath(`/parent/results/${studentId}`)
      return { error: null }
    }
    return { error: 'Could not save the result slip.' }
  }
  revalidatePath(`/parent/results/${studentId}`)
  return { error: null }
}

export async function sendParentMessage(
  studentId: string,
  subject: string,
  body: string,
): Promise<{ error: string | null }> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }
  if (!(await isFeatureEnabled('parent_portal'))) {
    return { error: 'Parent portal is not enabled.' }
  }

  const trimmed = body.trim()
  if (!trimmed) return { error: 'Message cannot be empty.' }

  const { error } = await supabase.rpc('send_parent_message', {
    p_student_id: studentId,
    p_subject: subject.trim() || null,
    p_body: trimmed,
  })
  if (error) return { error: error.message }

  revalidatePath(`/parent/messages/${studentId}`)
  return { error: null }
}
