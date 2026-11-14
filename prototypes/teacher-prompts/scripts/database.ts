/** Test-only owner setup, confined to tp_c. Never used by application requests. */
import { Pool } from "pg";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
const repo = fileURLToPath(new URL("../../../", import.meta.url));
export const localDb = {
  host: "localhost",
  port: 55432,
  user: "postgres",
  database: "tp_c",
};
export async function resetDatabase() {
  const paths = [
    "local/supabase_shim.sql",
    "migrations/0001_core.sql",
    "migrations/0002_calendar.sql",
    "migrations/0003_attendance_rpc.sql",
    "migrations/0004_prompt_scheduler.sql",
    "seed/demo_week.sql",
  ];
  if (paths.some((path) => !existsSync(repo + "supabase/v2/" + path)))
    throw new Error("TP_SCHEMA_PENDING");
  try {
    execFileSync(
      "createdb",
      ["-h", "localhost", "-p", "55432", "-U", "postgres", "tp_c"],
      { stdio: "pipe" },
    );
  } catch {
    /* Existing assigned database is expected. Connection below verifies it. */
  }
  const pool = new Pool(localDb);
  try {
    await pool.query(
      "DROP SCHEMA IF EXISTS public CASCADE; DROP SCHEMA IF EXISTS auth CASCADE; CREATE SCHEMA public;",
    );
  } finally {
    await pool.end();
  }
  for (const path of paths)
    execFileSync(
      "psql",
      [
        "-X",
        "-h",
        "localhost",
        "-p",
        "55432",
        "-U",
        "postgres",
        "-d",
        "tp_c",
        "-v",
        "ON_ERROR_STOP=1",
        "-f",
        repo + "supabase/v2/" + path,
      ],
      { stdio: "pipe", env: { PATH: process.env.PATH, NODE_ENV: "test" } },
    );
  const seeded = new Pool(localDb);
  try {
    await seeded.query("SELECT public.demo_shift_to_today()");
    // Only fake owner fixtures get a clock adjustment; UI mutations always use server time.
    const { rows } = await seeded.query<{ id: string }>(
      `UPDATE public.lessons SET scheduled_start_at=greatest(date_trunc('day',now() AT TIME ZONE 'Asia/Singapore') AT TIME ZONE 'Asia/Singapore',now()-interval '2 hours'),scheduled_end_at=now()+interval '1 minute',snoozed_until=NULL,snooze_count=0,plan_revision=plan_revision+1,overdue_at=now()+interval '2 hours' WHERE class_id='30000000-0000-4000-8000-000000000002' AND occurrence_date=(now() AT TIME ZONE 'Asia/Singapore')::date RETURNING id`,
    );
    if (rows.length !== 1) throw new Error("TP_MATH_FIXTURE_MISSING");
    await seeded.query("SELECT public.plan_prompts($1)", [rows[0].id]);
    return rows[0].id;
  } finally {
    await seeded.end();
  }
}
export async function ownerQuery<
  T extends import("pg").QueryResultRow = import("pg").QueryResultRow,
>(sql: string, values: unknown[] = []) {
  const pool = new Pool(localDb);
  try {
    return await pool.query<T>(sql, values);
  } finally {
    await pool.end();
  }
}
