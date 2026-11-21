import { afterEach, expect, it, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { fixture, now } from "../tests/fixture";
import { deferQuiet, planLesson } from "./lib/planner";
import { iso, minute } from "./lib/common";
import { dispatch } from "./push";
import { deliveryFixture } from "../tests/push_fixtures";

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});
it.each([
  ["06:59", "09:00"],
  ["07:00", "07:00"],
  ["21:59", "21:59"],
  ["22:00", "09:00"],
  ["00:01", "09:00"],
])("Singapore quiet boundary %s", (input, expected) => {
  for (const month of ["01", "07"]) {
    const base = "2027-" + month + "-07T",
      output = "2027-" + month + (input === "22:00" ? "-08T" : "-07T");
    expect(deferQuiet(Date.parse(base + input + ":00+08:00"))).toEqual(
      Date.parse(output + expected + ":00+08:00"),
    );
  }
});
it("plans four ordered stages and overdue at 09:15 without a fifth push", async () => {
  const { t, l } = await fixture();
  await t.run((ctx) => planLesson(ctx, l._id));
  const plans = (
    await t.run((ctx) => ctx.db.query("notification_plans").collect())
  ).sort((a, b) => a.due - b.due);
  expect(plans.map((p) => [p.kind, iso(p.due)])).toEqual(
    [
      ["heads_up", "2027-01-07T12:55:00.000Z"],
      ["attendance", "2027-01-07T13:00:00.000Z"],
      ["follow_up", "2027-01-07T13:15:00.000Z"],
      ["final", "2027-01-08T01:00:00.000Z"],
    ].map(([kind, date]) => [
      kind,
      iso(Date.parse(date) + (kind === "final" ? 0 : l.end - now)),
    ]),
  );
  expect(iso(l.overdue)).toBe("2027-01-08T01:15:00.000Z");
});
it("snapshots zero devices once and supersedes missed stages", async () => {
  const { t } = await fixture();
  vi.setSystemTime(now + 16 * minute);
  await Promise.all([
    t.mutation(internal.queue.tick, {}),
    t.mutation(internal.queue.tick, {}),
  ]);
  const logs = await t.run((ctx) => ctx.db.query("deliveries").collect());
  expect(logs.map((r) => r.outcome)).toEqual(["no_devices"]);
  const plans = await t.run((ctx) =>
    ctx.db.query("notification_plans").collect(),
  );
  expect(plans.filter((p) => p.status === "superseded")).toHaveLength(2);
  expect(plans.find((p) => p.kind === "follow_up")?.status).toBe("completed");
});
async function claimed() {
  const f = await fixture();
  await f.register();
  vi.setSystemTime(now + minute);
  expect(await f.t.mutation(internal.queue.tick, {})).toBe(1);
  const b = (await f.t.run((ctx) => ctx.db.query("outbox").first()))!;
  return { ...f, b, lease: { id: b._id, lease: b.lease! } };
}
it("deduplicates cron, prepare and acknowledgement and keeps accepted pushes terminal", async () => {
  const { t, lease, l } = await claimed();
  expect(await t.mutation(internal.queue.tick, {})).toBe(0);
  expect(await t.mutation(internal.queue.prepare, lease)).toMatchObject({
    mode: "dry_run",
  });
  expect(await t.mutation(internal.queue.prepare, lease)).toBeNull();
  const args = {
    ...lease,
    result: {
      accepted: true as const,
      transport: "dry_run" as const,
      provider_id: crypto.randomUUID(),
    },
  };
  expect(await t.mutation(internal.queue.finish, args)).toBe(true);
  expect(await t.mutation(internal.queue.finish, args)).toBe(false);
  await t.run((ctx) => planLesson(ctx, l._id));
  expect(await t.mutation(internal.queue.tick, {})).toBe(0);
  expect(await t.run((ctx) => ctx.db.query("outbox").collect())).toHaveLength(
    1,
  );
  expect(
    await t.run((ctx) => ctx.db.query("deliveries").collect()),
  ).toHaveLength(1);
});
it.each(["cancel", "substitute", "submit", "unregister", "disable"] as const)(
  "suppresses a claim before sending on %s",
  async (reason) => {
    const { t, admin, other, lead, base, mutation, lease } = await claimed();
    if (reason === "cancel")
      await admin.client.mutation(api.calendar.cancel_lesson, base);
    if (reason === "substitute")
      await admin.client.mutation(api.calendar.assign_lesson_teacher, {
        ...base,
        p_teacher_id: other.uuid,
        p_keep_previous_as_assistant: false,
      });
    if (reason === "submit")
      await lead.client.mutation(api.teacher.confirm_all_present_and_submit, {
        ...mutation(),
        p_expected_revision: "0",
        p_expected_feedback_revision: "0",
      });
    if (reason === "unregister") {
      const d = (await t.run((ctx) =>
        ctx.db.query("teacher_devices").first(),
      ))!;
      await lead.client.mutation(api.devices.unregister_device, {
        p_installation_id: d.installation,
      });
    }
    if (reason === "disable")
      await t.mutation(internal.settings.setFlag, {
        key: "teacher_prompts",
        enabled: false,
      });
    expect(await t.mutation(internal.queue.prepare, lease)).toBeNull();
    expect(
      await t.run((ctx) => ctx.db.query("deliveries").collect()),
    ).toHaveLength(0);
  },
);
it.each([false, true])(
  "410 invalidation is registration-version bound (rotated=%s)",
  async (rotate) => {
    const { t, lead, lease } = await claimed();
    await t.mutation(internal.queue.prepare, lease);
    const d = (await t.run((ctx) => ctx.db.query("teacher_devices").first()))!;
    if (rotate)
      await lead.client.mutation(api.devices.register_device, {
        p_installation_id: d.installation,
        p_token: "ab".repeat(32),
        p_environment: "sandbox",
      });
    await t.mutation(internal.queue.finish, {
      ...lease,
      result: {
        accepted: false,
        error_code: "unregistered",
        retryable: false,
        invalidate_device: true,
      },
    });
    expect(
      (await t.run((ctx) => ctx.db.get(d._id)))!.revoked === undefined,
    ).toBe(rotate);
  },
);
it("backs off one then five minutes, records three attempts and stops", async () => {
  const { t, b } = await claimed();
  for (let i = 1; i <= 3; i++) {
    const box = (await t.run((ctx) => ctx.db.get(b._id)))!;
    const lease = { id: b._id, lease: box.lease! };
    expect(await t.mutation(internal.queue.prepare, lease)).not.toBeNull();
    await t.mutation(internal.queue.finish, {
      ...lease,
      result: {
        accepted: false,
        error_code: "rate_limited",
        retryable: true,
        invalidate_device: false,
      },
    });
    const after = (await t.run((ctx) => ctx.db.get(b._id)))!;
    if (i < 3) {
      expect(after.available - Date.now()).toBeCloseTo(
        (i === 1 ? 1 : 5) * minute,
        -2,
      );
      vi.setSystemTime(after.available + 100);
      expect(await t.mutation(internal.queue.tick, {})).toBe(1);
    } else expect(after.status).toBe("failed");
  }
  expect(
    (await t.run((ctx) => ctx.db.query("deliveries").collect())).map(
      (r) => r.outcome,
    ),
  ).toEqual(["retry", "retry", "permanent_failure"]);
});
it.each([false, true])(
  "recovers abandoned claims and records unknown in-flight sends (prepared=%s)",
  async (prepared) => {
    const { t, lease } = await claimed();
    if (prepared) await t.mutation(internal.queue.prepare, lease);
    vi.setSystemTime(now + 4 * minute);
    expect(await t.mutation(internal.queue.tick, {})).toBe(prepared ? 0 : 1);
    expect(await t.mutation(internal.queue.prepare, lease)).toBeNull();
    if (prepared)
      expect(
        await t.run((ctx) => ctx.db.query("deliveries").first()),
      ).toMatchObject({ outcome: "unknown", code: "lease_expired" });
  },
);
it("never calls an APNs transport for a dry run", async () => {
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation(() => {
    throw Error("unexpected network");
  });
  const r = await dispatch(deliveryFixture());
  expect(r).toMatchObject({ accepted: true, transport: "dry_run" });
  expect(fetch).not.toHaveBeenCalled();
});
it("requires an explicitly matching environment for real sends", async () => {
  vi.stubEnv("APNS_DRY_RUN", "false");
  vi.stubEnv("APNS_ENV", "production");
  expect(await dispatch({ ...deliveryFixture(), mode: "apns" })).toMatchObject({
    accepted: false,
    error_code: "mode_mismatch",
  });
});
it("a claim crossing 22:00 waits until 09:00, spending no attempt and keeping the deadline", async () => {
  const { t, l, register } = await fixture(58);
  await register();
  vi.setSystemTime(now + 59 * minute);
  expect(await t.mutation(internal.queue.tick, {})).toBe(1);
  const box = (await t.run((ctx) => ctx.db.query("outbox").first()))!;
  vi.setSystemTime(now + 60 * minute);
  expect(
    await t.mutation(internal.queue.prepare, {
      id: box._id,
      lease: box.lease!,
    }),
  ).toBeNull();
  expect(await t.run((ctx) => ctx.db.get(box._id))).toMatchObject({
    attempts: 0,
    status: "pending",
    available: Date.parse("2027-01-08T01:00:00Z"),
  });
  expect((await t.run((ctx) => ctx.db.get(l._id)))!.overdue).toBe(l.overdue);
});
it("a quiet-hour tick defers overdue work through 07:00 to 09:00", async () => {
  const { t, register } = await fixture(58);
  await register();
  vi.setSystemTime(now + 61 * minute);
  expect(await t.mutation(internal.queue.tick, {})).toBe(0);
  vi.setSystemTime(Date.parse("2027-01-07T23:00:00Z"));
  expect(await t.mutation(internal.queue.tick, {})).toBe(0);
  expect(await t.run((ctx) => ctx.db.query("outbox").collect())).toHaveLength(
    0,
  );
});
