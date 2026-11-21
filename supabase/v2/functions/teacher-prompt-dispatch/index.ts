import { dispatchDuePrompts, type PromptDb } from "../_shared/prompt-dispatch.ts";
import { DryRunSender } from "../_shared/dry-run-sender.ts";
import { RestPromptDb } from "../_shared/rest-db.ts";
import { promptStrings } from "../_shared/prompt-strings.ts";

async function secretsMatch(provided: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([provided, expected].map(async (value) =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)))));
  let different = 0;
  for (let i = 0; i < left.length; i++) different |= left[i] ^ right[i];
  return different === 0;
}

async function emptyBody(request: Request): Promise<boolean> {
  const length = request.headers.get("content-length");
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > 1024)) return false;
  if (!request.body) return true;
  const reader = request.body.getReader();
  let total = 0;
  const decoder = new TextDecoder();
  let text = "";
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > 1024) { await reader.cancel(); return false; }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    if (!text.trim()) return true;
    const body = JSON.parse(text);
    return body !== null && typeof body === "object" && !Array.isArray(body) && Object.keys(body).length === 0;
  } catch { return false; }
  finally { reader.releaseLock(); }
}

/** The runnable prototype is deliberately dry-run only. It cannot construct ApnsSender. */
export function createHandler(options: { db: PromptDb; secret: string; now?: () => string }) {
  return async (request: Request): Promise<Response> => {
    const json = (body: unknown, status: number, headers = {}) =>
      Response.json(body, { status, headers: { "cache-control": "no-store", ...headers } });
    if (request.method !== "POST") return json({ error: promptStrings.methodNotAllowed }, 405, { allow: "POST" });
    if (options.secret.length < 32 || options.secret.length > 512) return json({ error: promptStrings.unavailable }, 503);
    const provided = request.headers.get("x-teacher-prompt-secret") ?? "";
    if (request.headers.has("authorization") || provided.length > 512 || !await secretsMatch(provided, options.secret)) {
      return json({ error: promptStrings.forbidden }, 403);
    }
    if (!await emptyBody(request)) return json({ error: promptStrings.invalidRequest }, 400);
    try {
      const result = await dispatchDuePrompts({ db: options.db, sender: new DryRunSender(),
        now: options.now ?? (() => new Date().toISOString()) });
      return json(result, 200);
    } catch { return json({ error: promptStrings.unavailable }, 503); }
  };
}

// This block is never executed by imports/tests. No .env reader or auto-deployment.
const deno = (globalThis as unknown as { Deno?: {
  env: { get(key: string): string | undefined };
  serve(handler: (request: Request) => Promise<Response>): unknown;
} }).Deno;
if (import.meta.main && deno) {
  const secret = deno.env.get("TEACHER_PROMPT_INVOKE_SECRET") ?? "";
  const mode = deno.env.get("TEACHER_PROMPT_MODE") ?? "dry_run";
  let handler: (request: Request) => Promise<Response>;
  try {
    if (mode !== "dry_run") throw new Error("TP_DRY_RUN_REQUIRED");
    const db = new RestPromptDb(deno.env.get("SUPABASE_URL") ?? "", deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", fetch);
    handler = createHandler({ db, secret });
  } catch {
    handler = async () => Response.json({ error: promptStrings.unavailable }, { status: 503 });
  }
  deno.serve(handler);
}
