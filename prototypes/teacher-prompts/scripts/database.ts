/** Test-only owner setup, confined to the explicit TP_DB. Never used by application requests. */
import { Pool } from "pg";
import { execFileSync } from "node:child_process";
import { assignedDatabase, databaseConfig } from "../lib/config";
import { existsSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
const repo = fileURLToPath(new URL("../../../", import.meta.url));
const assigned = assignedDatabase(process.env.TP_DB);
export const localDb = databaseConfig({
  TP_DB: assigned,
  TEACHER_PROMPTS_DEMO: "1",
});
const childEnv = { PATH: process.env.PATH, NODE_ENV: "test" as const };
export async function resetDatabase() {
  const paths = [
    "local/supabase_shim.sql",
    ...readdirSync(repo + "supabase/v2/migrations")
      .filter((name) => /^\d+.*\.sql$/.test(name))
      .sort()
      .map((name) => "migrations/" + name),
    "seed/demo_week.sql",
  ];
  if (paths.some((path) => !existsSync(repo + "supabase/v2/" + path)))
    throw new Error("TP_SCHEMA_PENDING");
  try {
    execFileSync(
      "createdb",
      ["-h", "localhost", "-p", "55432", "-U", "postgres", assigned],
      { stdio: "pipe", env: childEnv },
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
        assigned,
        "-v",
        "ON_ERROR_STOP=1",
        "-f",
        repo + "supabase/v2/" + path,
      ],
      { stdio: "pipe", env: childEnv },
    );
  const seeded = new Pool(localDb);
  try {
    await seeded.query("SELECT public.demo_shift_to_today()");
    // Only fake owner fixtures get a clock adjustment; UI mutations always use server time.
    const { rows } = await seeded.query<{ id: string }>(
      `UPDATE public.lessons SET scheduled_start_at=greatest(date_trunc('day',now() AT TIME ZONE 'Asia/Singapore') AT TIME ZONE 'Asia/Singapore',date_bin(interval '5 minutes',now(),timestamptz '2000-01-01 00:00:00+08')-interval '115 minutes'),scheduled_end_at=date_bin(interval '5 minutes',now(),timestamptz '2000-01-01 00:00:00+08')+interval '5 minutes',snoozed_until=NULL,snooze_count=0,plan_revision=plan_revision+1,overdue_at=now()+interval '2 hours' WHERE class_id='30000000-0000-4000-8000-000000000002' AND occurrence_date=(now() AT TIME ZONE 'Asia/Singapore')::date RETURNING id`,
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
