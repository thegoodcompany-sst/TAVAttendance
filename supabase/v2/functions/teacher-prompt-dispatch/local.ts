import { setTimeout as delay } from "node:timers/promises";
import { LocalPromptDb } from "../_shared/local-db.ts";
import { DryRunSender } from "../_shared/dry-run-sender.ts";
import { dispatchDuePrompts } from "../_shared/prompt-dispatch.ts";
import { promptStrings } from "../_shared/prompt-strings.ts";

export function parseLocalArgs(args: string[]): { watch: boolean; fixedNow?: string } {
  const watch = args.includes("--watch");
  const once = args.includes("--once");
  if (watch === once) throw new Error("TP_INVALID_ARGUMENTS");
  let fixedNow: string | undefined;
  const seen = new Set<string>();
  for (let index = 0; index < args.length; index++) {
    const argument = args[index];
    if (seen.has(argument)) throw new Error("TP_INVALID_ARGUMENTS");
    seen.add(argument);
    if (argument === "--watch" || argument === "--once") continue;
    if (argument !== "--now" || !once) throw new Error("TP_INVALID_ARGUMENTS");
    const value = args[++index];
    if (!value || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) ||
      !Number.isFinite(Date.parse(value))) throw new Error("TP_INVALID_ARGUMENTS");
    fixedNow = new Date(value).toISOString();
  }
  return { watch, fixedNow };
}

/** One bounded refresh attempt per tick; sanitized health reporting, dispatch continues. */
export async function refreshBeforeDispatch(db: { refresh(): Promise<void> }, report: (message: string) => void) {
  try { await db.refresh(); }
  catch { report(promptStrings.calendarRefreshFailed); }
}

export async function main(args: string[], env: Record<string, string | undefined>) {
  const options = parseLocalArgs(args);
  if (env.TEACHER_PROMPTS_DEMO !== "1") throw new Error("TP_DEMO_REQUIRED");
  const db = new LocalPromptDb(env.TEACHER_PROMPTS_DATABASE_URL, env.TEACHER_PROMPTS_DB_NAME);
  const stop = new AbortController();
  const shutdown = () => stop.abort();
  process.once("SIGINT", shutdown);
  process.once("SIGTERM", shutdown);
  try {
    if (!await db.isDemo()) throw new Error("TP_DEMO_REQUIRED");
    const now = () => options.fixedNow ?? new Date().toISOString();
    do {
      await refreshBeforeDispatch(db, (message) => console.error(message));
      const result = await dispatchDuePrompts({ db, sender: new DryRunSender(), now });
      console.log(JSON.stringify({ transport: "dry_run", ...result }));
      if (!options.watch || stop.signal.aborted) break;
      try { await delay(60_000, undefined, { signal: stop.signal }); }
      catch { if (!stop.signal.aborted) throw new Error("TP_TIMER_ERROR"); }
    } while (!stop.signal.aborted);
  } finally {
    process.removeListener("SIGINT", shutdown);
    process.removeListener("SIGTERM", shutdown);
    await db.close();
  }
}

if (import.meta.main) {
  main(process.argv.slice(2), {
    TEACHER_PROMPTS_DATABASE_URL: process.env.TEACHER_PROMPTS_DATABASE_URL,
    TEACHER_PROMPTS_DB_NAME: process.env.TEACHER_PROMPTS_DB_NAME,
    TEACHER_PROMPTS_DEMO: process.env.TEACHER_PROMPTS_DEMO,
  }).catch(() => { console.error(promptStrings.workerFailed); process.exitCode = 1; });
}
