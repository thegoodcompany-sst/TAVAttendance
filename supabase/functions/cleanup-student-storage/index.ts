// deno-lint-ignore-file no-import-prefix -- Edge Functions pin JSR imports at the call site.
import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2.109.0";

const QUEUE_TABLE = "student_storage_cleanup_queue";
const UPLOAD_INTENTS_TABLE = "result_slip_upload_intents";
const PRIVATE_STUDENT_BUCKETS = ["result-slips", "student-photos"] as const;
const INVOKE_HEADER = "x-storage-cleanup-secret";
const MAX_BATCH_SIZE = 5;
const MAX_STALE_UPLOAD_BATCH_SIZE = 100;
const PAGE_SIZE = 100;
const REMOVE_BATCH_SIZE = 100;
const MAX_CLEANUP_PASSES = 3;
const MAX_LIST_CALLS_PER_INVOCATION = 500;
const MAX_REMOVE_CALLS_PER_INVOCATION = 500;
const INVOCATION_BUDGET_MS = 85 * 1000;
const CLAIM_HEADROOM_MS = 5 * 1000;
const LEASE_DURATION_MS = 10 * 60 * 1000;
const MAX_SECRET_LENGTH = 512;
const GENERIC_FAILURE = "storage_cleanup_failed";
const UUID_HEX_PATTERN = /^[0-9a-f]{32}$/;

interface QueueRow {
  id: string;
  student_id: string;
  attempts: number | null;
  completed_at: string | null;
}

interface UploadIntentRow {
  path: string;
  finalized_result_id: string | null;
}

interface WorkBudget {
  listCalls: number;
  removeCalls: number;
  deadline: number;
}

interface RootMatches {
  prefixes: Set<string>;
  files: Set<string>;
}

function response(
  processed: number,
  failed: number,
  status = 200,
  headers?: HeadersInit,
) {
  return Response.json(
    { processed, failed },
    {
      status,
      headers: {
        "Cache-Control": "no-store",
        ...headers,
      },
    },
  );
}

async function secretsMatch(
  provided: string,
  expected: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const left = new Uint8Array(providedHash);
  const right = new Uint8Array(expectedHash);
  let difference = left.length ^ right.length;

  for (let index = 0; index < Math.max(left.length, right.length); index++) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }

  return difference === 0;
}

function normalizeUuidLike(value: string): string | null {
  const unwrapped = value.startsWith("{") && value.endsWith("}")
    ? value.slice(1, -1)
    : value;
  const hex = unwrapped.replaceAll("-", "").toLowerCase();
  return UUID_HEX_PATTERN.test(hex) ? hex : null;
}

function canonicalUuid(hex: string): string {
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
}

function joinStoragePath(folder: string, name: string): string {
  return folder ? `${folder}/${name}` : name;
}

function consumeListBudget(budget: WorkBudget): void {
  budget.listCalls += 1;
  if (
    Date.now() >= budget.deadline ||
    budget.listCalls > MAX_LIST_CALLS_PER_INVOCATION
  ) {
    throw new Error("cleanup budget exhausted");
  }
}

function consumeRemoveBudget(budget: WorkBudget): void {
  budget.removeCalls += 1;
  if (
    Date.now() >= budget.deadline ||
    budget.removeCalls > MAX_REMOVE_CALLS_PER_INVOCATION
  ) {
    throw new Error("cleanup budget exhausted");
  }
}

async function listObjects(
  supabase: SupabaseClient,
  bucketName: string,
  folder: string,
  budget: WorkBudget,
  offset = 0,
) {
  consumeListBudget(budget);
  const { data, error } = await supabase.storage.from(bucketName).list(folder, {
    limit: PAGE_SIZE,
    offset,
    sortBy: { column: "name", order: "asc" },
  });
  if (error) throw new Error("storage list failed");
  return data ?? [];
}

async function removeObjects(
  supabase: SupabaseClient,
  bucketName: string,
  paths: string[],
  budget: WorkBudget,
): Promise<void> {
  for (let index = 0; index < paths.length; index += REMOVE_BATCH_SIZE) {
    consumeRemoveBudget(budget);
    const { error } = await supabase.storage
      .from(bucketName)
      .remove(paths.slice(index, index + REMOVE_BATCH_SIZE));
    if (error) throw new Error("storage remove failed");
  }
}

/**
 * Drains a tree in fixed-size windows. Always listing at offset zero after a
 * mutation avoids skipping objects as the remaining result set shifts.
 */
async function removeTreePass(
  supabase: SupabaseClient,
  bucketName: string,
  prefix: string,
  budget: WorkBudget,
): Promise<void> {
  const pendingFolders = [prefix];

  while (pendingFolders.length > 0) {
    const folder = pendingFolders.pop()!;
    const objects = await listObjects(supabase, bucketName, folder, budget);
    if (objects.length === 0) continue;

    const files: string[] = [];
    const childFolders: string[] = [];
    for (const object of objects) {
      if (!object.name) continue;
      const path = joinStoragePath(folder, object.name);
      if (object.id) files.push(path);
      else childFolders.push(path);
    }

    await removeObjects(supabase, bucketName, files, budget);

    // Revisit the parent after this window. Child folders disappear from its
    // listing once their contents have been deleted.
    pendingFolders.push(folder);
    pendingFolders.push(...childFolders);
  }
}

async function prefixIsEmpty(
  supabase: SupabaseClient,
  bucketName: string,
  prefix: string,
  budget: WorkBudget,
): Promise<boolean> {
  consumeListBudget(budget);
  const { data, error } = await supabase.storage.from(bucketName).list(prefix, {
    limit: 1,
  });
  if (error) throw new Error("storage verification failed");
  return (data?.length ?? 0) === 0;
}

async function clearStoragePrefix(
  supabase: SupabaseClient,
  bucketName: string,
  prefix: string,
  budget: WorkBudget,
): Promise<void> {
  for (let pass = 0; pass < MAX_CLEANUP_PASSES; pass++) {
    await removeTreePass(supabase, bucketName, prefix, budget);
    if (await prefixIsEmpty(supabase, bucketName, prefix, budget)) return;
  }

  throw new Error("storage cleanup incomplete");
}

async function findEquivalentRootObjects(
  supabase: SupabaseClient,
  bucketName: string,
  normalizedStudentId: string,
  budget: WorkBudget,
): Promise<RootMatches> {
  const matches: RootMatches = { prefixes: new Set(), files: new Set() };
  let offset = 0;

  while (true) {
    const objects = await listObjects(supabase, bucketName, "", budget, offset);
    for (const object of objects) {
      if (
        !object.name || normalizeUuidLike(object.name) !== normalizedStudentId
      ) continue;
      if (object.id) matches.files.add(object.name);
      else matches.prefixes.add(object.name);
    }

    if (objects.length < PAGE_SIZE) break;
    offset += objects.length;
  }

  return matches;
}

async function removeStudentPrivateFiles(
  supabase: SupabaseClient,
  studentId: string,
  budget: WorkBudget,
): Promise<void> {
  const normalizedStudentId = normalizeUuidLike(studentId);
  if (!normalizedStudentId) throw new Error("invalid student identifier");

  const canonicalPrefix = canonicalUuid(normalizedStudentId);
  for (const bucketName of PRIVATE_STUDENT_BUCKETS) {
    // Always cover the canonical path first. Root scans below additionally find
    // legacy uppercase, braced, or unhyphenated spellings that normalize to the
    // exact same UUID; arbitrary prefix matching is deliberately not used.
    await clearStoragePrefix(supabase, bucketName, canonicalPrefix, budget);

    for (let pass = 0; pass < MAX_CLEANUP_PASSES; pass++) {
      const matches = await findEquivalentRootObjects(
        supabase,
        bucketName,
        normalizedStudentId,
        budget,
      );

      for (const prefix of matches.prefixes) {
        await clearStoragePrefix(supabase, bucketName, prefix, budget);
      }
      await removeObjects(supabase, bucketName, [...matches.files], budget);

      const remaining = await findEquivalentRootObjects(
        supabase,
        bucketName,
        normalizedStudentId,
        budget,
      );
      if (remaining.prefixes.size === 0 && remaining.files.size === 0) break;
      if (pass === MAX_CLEANUP_PASSES - 1) {
        throw new Error("storage cleanup incomplete");
      }
    }
  }
}

async function removeExpiredUploadIntents(
  supabase: SupabaseClient,
  budget: WorkBudget,
): Promise<number> {
  const claimedAt = new Date().toISOString();
  const leaseCutoff = new Date(Date.now() - LEASE_DURATION_MS).toISOString();
  const { data, error } = await supabase
    .from(UPLOAD_INTENTS_TABLE)
    .select("path, finalized_result_id")
    .lt("expires_at", claimedAt)
    .or(`cleanup_claimed_at.is.null,cleanup_claimed_at.lt.${leaseCutoff}`)
    .order("expires_at", { ascending: true })
    .limit(MAX_STALE_UPLOAD_BATCH_SIZE);
  if (error) throw new Error("upload intent lookup failed");

  const paths = ((data ?? []) as UploadIntentRow[])
    .map((row) => row.path)
    .filter((path): path is string => typeof path === "string");
  if (paths.length === 0) return 0;

  // Claim before touching Storage. The atomic finalizer locks and marks a live
  // intent; once this compare-and-set wins, it can no longer commit a result
  // row that points at an object this worker is about to remove.
  const { data: claimed, error: claimError } = await supabase
    .from(UPLOAD_INTENTS_TABLE)
    .update({ cleanup_claimed_at: claimedAt })
    .in("path", paths)
    .lt("expires_at", claimedAt)
    .or(`cleanup_claimed_at.is.null,cleanup_claimed_at.lt.${leaseCutoff}`)
    .select("path, finalized_result_id");
  if (claimError) throw new Error("upload intent claim failed");

  const claimedRows = (claimed ?? []) as UploadIntentRow[];
  const claimedPaths = claimedRows
    .map((row) => row.path)
    .filter((path): path is string => typeof path === "string");
  if (claimedPaths.length === 0) return 0;

  // Unfinalized paths, and paths whose result row was later erased (FK SET
  // NULL), are abandoned. A finalized result that still exists keeps its file;
  // only its now-expired token tombstone is removed.
  const abandonedPaths = claimedRows
    .filter((row) => !row.finalized_result_id)
    .map((row) => row.path)
    .filter((path): path is string => typeof path === "string");

  try {
    await removeObjects(supabase, "result-slips", abandonedPaths, budget);
  } catch {
    await supabase
      .from(UPLOAD_INTENTS_TABLE)
      .update({ cleanup_claimed_at: null })
      .in("path", claimedPaths)
      .eq("cleanup_claimed_at", claimedAt);
    throw new Error("expired upload removal failed");
  }

  const { error: deleteError } = await supabase
    .from(UPLOAD_INTENTS_TABLE)
    .delete()
    .in("path", claimedPaths)
    .eq("cleanup_claimed_at", claimedAt);
  if (deleteError) {
    await supabase
      .from(UPLOAD_INTENTS_TABLE)
      .update({ cleanup_claimed_at: null })
      .in("path", claimedPaths)
      .eq("cleanup_claimed_at", claimedAt);
    throw new Error("upload intent completion failed");
  }
  return claimedPaths.length;
}

async function claimJob(
  supabase: SupabaseClient,
  candidate: QueueRow,
): Promise<QueueRow | null> {
  const claimedAt = new Date().toISOString();
  let query = supabase
    .from(QUEUE_TABLE)
    .update({ completed_at: claimedAt, last_attempt_at: claimedAt })
    .eq("id", candidate.id);

  query = candidate.completed_at === null
    ? query.is("completed_at", null)
    : query.eq("completed_at", candidate.completed_at);

  const { data, error } = await query
    .select("id, student_id, attempts, completed_at")
    .maybeSingle();
  if (error) throw new Error("queue claim failed");
  return data as QueueRow | null;
}

async function deleteCompletedJob(
  supabase: SupabaseClient,
  job: QueueRow,
): Promise<void> {
  const { data, error } = await supabase
    .from(QUEUE_TABLE)
    .delete()
    .eq("id", job.id)
    .eq("completed_at", job.completed_at!)
    .select("id");

  if (error || data?.length !== 1) throw new Error("queue completion failed");
}

async function releaseFailedJob(
  supabase: SupabaseClient,
  job: QueueRow,
): Promise<void> {
  const attempts =
    Number.isSafeInteger(job.attempts) && (job.attempts ?? 0) >= 0
      ? job.attempts!
      : 0;

  const { data, error } = await supabase
    .from(QUEUE_TABLE)
    .update({
      attempts: Math.min(attempts + 1, 2_147_483_647),
      last_error: GENERIC_FAILURE,
      completed_at: null,
    })
    .eq("id", job.id)
    .eq("completed_at", job.completed_at!)
    .select("id");

  if (error || data?.length !== 1) throw new Error("queue release failed");
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return response(0, 0, 405, { Allow: "POST" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const invokeSecret = Deno.env.get("STORAGE_CLEANUP_INVOKE_SECRET");
  if (
    !supabaseUrl || !serviceRoleKey || !invokeSecret ||
    invokeSecret.length < 32 || invokeSecret.length > MAX_SECRET_LENGTH
  ) {
    return response(0, 0, 503);
  }

  // This endpoint authenticates only with its dedicated secret. A caller's
  // bearer token is never accepted or forwarded to the internal client.
  if (request.headers.has("authorization")) return response(0, 0, 403);
  const providedSecret = request.headers.get(INVOKE_HEADER) ?? "";
  if (
    providedSecret.length > MAX_SECRET_LENGTH ||
    !(await secretsMatch(providedSecret, invokeSecret))
  ) {
    return response(0, 0, 403);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });

  let processed = 0;
  let failed = 0;
  let infrastructureFailure = false;
  const budget: WorkBudget = {
    listCalls: 0,
    removeCalls: 0,
    deadline: Date.now() + INVOCATION_BUDGET_MS,
  };

  try {
    processed += await removeExpiredUploadIntents(supabase, budget);
    const leaseCutoff = new Date(Date.now() - LEASE_DURATION_MS).toISOString();
    const { data, error } = await supabase
      .from(QUEUE_TABLE)
      .select("id, student_id, attempts, completed_at")
      .or(`completed_at.is.null,completed_at.lt.${leaseCutoff}`)
      .order("requested_at", { ascending: true })
      .limit(MAX_BATCH_SIZE);
    if (error) return response(0, 0, 500);

    for (const candidate of (data ?? []) as QueueRow[]) {
      if (Date.now() + CLAIM_HEADROOM_MS >= budget.deadline) break;
      let job: QueueRow | null = null;
      try {
        job = await claimJob(supabase, candidate);
        if (!job) continue;
        await removeStudentPrivateFiles(supabase, job.student_id, budget);
        await deleteCompletedJob(supabase, job);
        processed += 1;
      } catch {
        failed += 1;
        if (job) await releaseFailedJob(supabase, job);
        else infrastructureFailure = true;
      }
    }
  } catch {
    infrastructureFailure = true;
  }

  return response(processed, failed, infrastructureFailure ? 500 : 200);
});
