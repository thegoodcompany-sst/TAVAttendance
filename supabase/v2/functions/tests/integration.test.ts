import { afterAll, beforeAll, beforeEach, describe, expect, test } from "bun:test";
import pg from "pg";
import { LocalPromptDb, localDatabaseConfig } from "../_shared/local-db.ts";
import { dispatchDuePrompts, type PromptDb, type SendResult } from "../_shared/prompt-dispatch.ts";
import { DryRunSender } from "../_shared/dry-run-sender.ts";
import { NOW } from "./fixtures.ts";

// Explicit opt-in only. Never take the connection target from generic database env.
const enabled = process.env.TEACHER_PROMPTS_RUN_INTEGRATION === "1";
const URL = "postgresql://postgres@localhost:55432/tp_b";
const lesson = "91000000-0000-4000-8000-000000000001";
const classId = "91000000-0000-4000-8000-000000000002";
const teacher = "10000000-0000-4000-8000-000000000011";
const device = "80000000-0000-4000-8000-000000000011";
const failure: Extract<SendResult, { accepted: false }> = {
  accepted: false, error_code: "timeout", retryable: true, invalidate_device: false,
};

describe.skipIf(!enabled)("tp_b local Postgres integration (dry-run only)", () => {
  let pool: pg.Pool;
  let db: LocalPromptDb;
  let plans: { id: string; status: string }[];
  let savedDevice: { last_seen_at: Date; revoked_at: Date | null };
  async function cleanup() {
    await pool.query(`
      DELETE FROM public.notification_deliveries WHERE outbox_id IN
        (SELECT o.id FROM public.notification_outbox o JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=$1);
    `, [lesson]);
    await pool.query("DELETE FROM public.notification_outbox WHERE plan_id IN (SELECT id FROM public.notification_plans WHERE lesson_id=$1)", [lesson]);
    await pool.query("DELETE FROM public.notification_plans WHERE lesson_id=$1", [lesson]);
    await pool.query("DELETE FROM public.lesson_submissions WHERE lesson_id=$1", [lesson]);
    await pool.query("DELETE FROM public.lessons WHERE id=$1", [lesson]);
  }
  beforeAll(async () => {
    pool = new pg.Pool(localDatabaseConfig(URL, "tp_b"));
    db = new LocalPromptDb(URL, "tp_b");
    expect(await db.isDemo()).toBe(true);
    const state = await pool.query("SELECT anchor_date::text AS anchor FROM public.demo_seed_state");
    expect(state.rows[0].anchor).toBe("2027-01-07");
    plans = (await pool.query("SELECT id,status FROM public.notification_plans WHERE lesson_id<>$1", [lesson])).rows;
    savedDevice = (await pool.query("SELECT last_seen_at,revoked_at FROM public.teacher_devices WHERE id=$1", [device])).rows[0];
    // Isolate only the fixture's scheduler work; restore canonical plan states afterward.
    await pool.query("UPDATE public.notification_plans SET status='cancelled' WHERE lesson_id<>$1", [lesson]);
    await pool.query("INSERT INTO public.classes(id,short_label,subject) VALUES($1,'Demo Worker Fixture','Demo') ON CONFLICT DO NOTHING", [classId]);
  });
  beforeEach(async () => {
    await cleanup();
    await pool.query("UPDATE public.feature_flags SET enabled=(key='teacher_prompts')");
    await pool.query("UPDATE public.teacher_devices SET revoked_at=NULL,last_seen_at=$2::timestamptz WHERE id=$1", [device, NOW]);
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(`INSERT INTO public.lessons(id,class_id,occurrence_date,scheduled_start_at,scheduled_end_at,accountable_teacher_id,overdue_at)
        VALUES($1,$2,'2027-01-07','2027-01-07T11:00:00Z','2027-01-07T13:00:00Z',$3,'2027-01-08T01:15:00Z')`, [lesson, classId, teacher]);
      await client.query("INSERT INTO public.lesson_staff(lesson_id,teacher_id,assignment_kind) VALUES($1,$2,'regular')", [lesson, teacher]);
      await client.query("COMMIT");
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  });
  afterAll(async () => {
    if (!pool) return;
    try {
      await cleanup();
      await pool.query("DELETE FROM public.classes WHERE id=$1", [classId]);
      if (plans) await pool.query(`UPDATE public.notification_plans p SET status=x.status
        FROM jsonb_to_recordset($1::jsonb) AS x(id uuid,status text) WHERE p.id=x.id`, [JSON.stringify(plans)]);
      if (savedDevice) await pool.query("UPDATE public.teacher_devices SET last_seen_at=$2,revoked_at=$3 WHERE id=$1",
        [device, savedDevice.last_seen_at, savedDevice.revoked_at]);
      await pool.query("UPDATE public.feature_flags SET enabled=(key='teacher_prompts')");
    } finally { await db.close(); await pool.end(); }
  });
  test("claim/prepare/dry-run/receipt and second tick has no resend", async () => {
    const args = { db, sender: new DryRunSender(), now: () => NOW };
    expect(await dispatchDuePrompts(args)).toEqual({ claimed: 1, accepted: 1, failed: 0, suppressed: 0 });
    expect((await dispatchDuePrompts(args)).claimed).toBe(0);
    const rows = (await pool.query(`SELECT d.transport,d.outcome,d.provider_id=o.id AS stable_id
      FROM public.notification_deliveries d JOIN public.notification_outbox o ON o.id=d.outbox_id
      JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=$1`, [lesson])).rows;
    expect(rows).toEqual([{ transport: "dry_run", outcome: "accepted", stable_id: true }]);
  });
  test("database claim contains only contract keys and decimal string revision", async () => {
    const [claim] = await db.claim(NOW, 50);
    expect(Object.keys(claim).sort()).toEqual(["outbox_id", "plan_id", "lesson_id", "kind", "recipient_id", "device_id",
      "plan_revision", "lease_token", "lease_until", "attempt_no"].sort());
    expect(typeof claim.plan_revision).toBe("string");
    expect(typeof claim.lease_until).toBe("string");
    const prepared = await db.prepare(claim, NOW);
    expect(prepared?.mode).toBe("dry_run");
    expect(prepared?.collapse_id).toBe(`tp:${lesson}`);
    expect(prepared?.thread_id).toBe(`teacher-lesson:${lesson}`);
    expect(Date.parse(prepared!.expires_at)).toBeLessThanOrEqual(Date.parse(NOW) + 3_600_000);
  });
  test("submission committed after claim stops every send", async () => {
    const wrapped: PromptDb = {
      claim: async (now, limit) => {
        const claims = await db.claim(now, limit);
        await pool.query(`INSERT INTO public.lesson_submissions(lesson_id,register_revision,feedback_revision,submitted_by,submitted_at,mutation_id)
          VALUES($1,0,0,$2,$3,gen_random_uuid())`, [lesson, teacher, NOW]);
        return claims;
      },
      prepare: db.prepare.bind(db), sent: db.sent.bind(db), failed: db.failed.bind(db),
    };
    let sends = 0;
    const result = await dispatchDuePrompts({ db: wrapped, now: () => NOW, sender: { send: async () => { sends++; return failure; } } });
    expect(result.suppressed).toBe(1); expect(sends).toBe(0);
    expect((await db.claim(NOW, 50)).length).toBe(0);
  });
  test("SQL retries after one and five minutes then stops at three attempts", async () => {
    for (const now of [NOW, "2027-01-07T13:06:00Z", "2027-01-07T13:11:00Z"]) {
      const claims = await db.claim(now, 1);
      expect(claims).toHaveLength(1);
      expect(await db.prepare(claims[0], now)).not.toBeNull();
      expect(await db.failed(claims[0], failure, now)).toBe(true);
      if (now === NOW) expect(await db.claim(NOW, 1)).toHaveLength(0);
    }
    const row = (await pool.query(`SELECT o.status,o.attempt_count FROM public.notification_outbox o
      JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=$1 AND p.kind='heads_up'`, [lesson])).rows[0];
    expect(row).toEqual({ status: "failed", attempt_count: 3 });
  });
  test("410 invalidation uses prepared device version; a rotation survives", async () => {
    const [claim] = await db.claim(NOW, 50); await db.prepare(claim, NOW);
    await pool.query("UPDATE public.teacher_devices SET last_seen_at=last_seen_at+interval '1 second' WHERE id=$1", [device]);
    expect(await db.failed(claim, { accepted: false, error_code: "unregistered", retryable: false, invalidate_device: true }, NOW)).toBe(true);
    expect((await pool.query("SELECT revoked_at FROM public.teacher_devices WHERE id=$1", [device])).rows[0].revoked_at).toBeNull();
  });
  test("BadDeviceToken invalidates only the prepared registration", async () => {
    const [claim] = await db.claim(NOW, 50); await db.prepare(claim, NOW);
    await db.failed(claim, { accepted: false, error_code: "bad_device_token", retryable: false, invalidate_device: true }, NOW);
    expect((await pool.query("SELECT revoked_at IS NOT NULL AS revoked FROM public.teacher_devices WHERE id=$1", [device])).rows[0].revoked).toBe(true);
  });
  test("quiet-hour prepare releases unused attempt without a receipt", async () => {
    const [claim] = await db.claim("2027-01-07T13:59:59Z", 50);
    expect(await db.prepare(claim, "2027-01-07T14:00:00Z")).toBeNull();
    const row = (await pool.query("SELECT status,attempt_count,lease_token FROM public.notification_outbox WHERE id=$1", [claim.outbox_id])).rows[0];
    expect(row).toEqual({ status: "pending", attempt_count: 0, lease_token: null });
    expect((await pool.query("SELECT count(*)::int AS n FROM public.notification_deliveries WHERE outbox_id=$1", [claim.outbox_id])).rows[0].n).toBe(0);
  });
  test("lease reclaim logs unknown; old lease cannot complete", async () => {
    const [old] = await db.claim(NOW, 50);
    const [fresh] = await db.claim("2027-01-07T13:07:01Z", 50);
    expect(fresh.outbox_id).toBe(old.outbox_id); expect(fresh.lease_token).not.toBe(old.lease_token);
    expect(await db.sent(old, { accepted: true, provider_id: old.outbox_id, transport: "dry_run" }, "2027-01-07T13:07:01Z")).toBe(false);
    const outcomes = (await pool.query("SELECT outcome FROM public.notification_deliveries WHERE outbox_id=$1", [old.outbox_id])).rows;
    expect(outcomes).toEqual([{ outcome: "unknown" }]);
  });
  test("concurrent ticks claim disjoint outbox rows", async () => {
    const [first, second] = await Promise.all([db.claim(NOW, 50), db.claim(NOW, 50)]);
    const ids = [...first, ...second].map((claim) => claim.outbox_id);
    expect(ids.length).toBe(1); expect(new Set(ids).size).toBe(ids.length);
  });
  test("flag disabled between claim and prepare suppresses pending work", async () => {
    const [claim] = await db.claim(NOW, 50);
    await pool.query("UPDATE public.feature_flags SET enabled=false WHERE key='teacher_prompts'");
    expect(await db.prepare(claim, NOW)).toBeNull();
    expect(await db.claim(NOW, 50)).toEqual([]);
  });
  test("no-device plan records terminal no_devices instead of fake acceptance", async () => {
    await pool.query("UPDATE public.teacher_devices SET revoked_at=$2 WHERE id=$1", [device, NOW]);
    expect(await db.claim(NOW, 50)).toEqual([]);
    const outcomes = (await pool.query(`SELECT d.transport,d.outcome FROM public.notification_deliveries d
      JOIN public.notification_outbox o ON o.id=d.outbox_id JOIN public.notification_plans p ON p.id=o.plan_id
      WHERE p.lesson_id=$1`, [lesson])).rows;
    expect(outcomes).toEqual([{ transport: "none", outcome: "no_devices" }]);
  });
  test("sender exception stores only a sanitized retryable transport code", async () => {
    await dispatchDuePrompts({ db, now: () => NOW, sender: { send: async () => { throw new Error("Demo Student 01 private token"); } } });
    const rows = (await pool.query(`SELECT d.error_code,d.outcome FROM public.notification_deliveries d
      JOIN public.notification_outbox o ON o.id=d.outbox_id JOIN public.notification_plans p ON p.id=o.plan_id
      WHERE p.lesson_id=$1`, [lesson])).rows;
    expect(rows).toEqual([{ error_code: "transport_error", outcome: "retry" }]);
  });
  test("provider status codes survive the database allowlist", async () => {
    await dispatchDuePrompts({ db, now: () => NOW, sender: { send: async () =>
      ({ accepted: false, error_code: "server_error", retryable: true, invalidate_device: false }) } });
    const rows = (await pool.query(`SELECT d.error_code,d.outcome FROM public.notification_deliveries d
      JOIN public.notification_outbox o ON o.id=d.outbox_id JOIN public.notification_plans p ON p.id=o.plan_id
      WHERE p.lesson_id=$1`, [lesson])).rows;
    expect(rows).toEqual([{ error_code: "server_error", outcome: "retry" }]);
  });
});
