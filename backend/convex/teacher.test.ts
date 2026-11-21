import { afterEach, expect, it, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { fixture, now } from "../tests/fixture";
import { day, minute } from "./lib/common";

afterEach(() => vi.useRealTimers());
it("limits today, deep links and writes to the current lead and admin", async () => {
  const { lead, other, admin, t, base, mutation } = await fixture();
  expect(
    (await lead.client.query(api.teacher.my_lessons_today, {})).lessons,
  ).toHaveLength(1);
  expect(
    (await admin.client.query(api.teacher.my_lessons_today, {})).lessons,
  ).toHaveLength(1);
  expect(
    (await other.client.query(api.teacher.my_lessons_today, {})).lessons,
  ).toHaveLength(0);
  await expect(
    other.client.query(api.teacher.lesson_for_prompt, base),
  ).rejects.toThrow("TP_NOT_AVAILABLE");
  await expect(
    other.client.mutation(api.teacher.mark_all_present, {
      ...mutation(),
      p_expected_revision: "0",
    }),
  ).rejects.toThrow("TP_NOT_AVAILABLE");
  await expect(t.query(api.teacher.lesson_for_prompt, base)).rejects.toThrow(
    "sessionExpired",
  );
});
it("removes Study Space from review, lists and missing submissions at source", async () => {
  const { t, l, admin, lead, base } = await fixture();
  await t.run((ctx) => ctx.db.patch(l.class, { studySpace: true }));
  expect(
    (await lead.client.query(api.teacher.my_lessons_today, {})).lessons,
  ).toHaveLength(0);
  expect(
    (
      await admin.client.query(api.calendar.admin_missing_submissions, {
        p_from: "2027-01-01",
        p_until: "2027-01-10",
      })
    ).lessons,
  ).toHaveLength(0);
  await expect(
    admin.client.query(api.teacher.lesson_for_prompt, base),
  ).rejects.toThrow("TP_NOT_AVAILABLE");
});
it("rechecks authority before replay even if the former lead stays on as assistant", async () => {
  const { t, lead, other, admin, base, mutation, detail } = await fixture();
  const arg = { ...mutation(), p_expected_revision: "0" };
  await lead.client.mutation(api.teacher.mark_all_present, arg);
  await admin.client.mutation(api.calendar.assign_lesson_teacher, {
    ...base,
    p_teacher_id: other.uuid,
    p_keep_previous_as_assistant: true,
  });
  await expect(detail()).rejects.toThrow("TP_NOT_AVAILABLE");
  await expect(
    lead.client.mutation(api.teacher.mark_all_present, arg),
  ).rejects.toThrow("TP_NOT_AVAILABLE");
  expect(
    (await other.client.query(api.teacher.lesson_for_prompt, base)).lesson
      .is_accountable,
  ).toBe(true);
  expect(
    (await t.run((ctx) => ctx.db.query("lesson_staff").collect()))
      .map((s) => s.assignment)
      .sort(),
  ).toEqual(["assistant", "substitute"]);
  await expect(
    admin.client.mutation(api.calendar.assign_lesson_teacher, {
      ...base,
      p_teacher_id: admin.uuid,
      p_keep_previous_as_assistant: false,
    }),
  ).rejects.toThrow("TP_INVALID_INPUT");
});
it("records specific revisions and fills only unmarked rows atomically", async () => {
  const { t, lead, mutation, detail } = await fixture();
  const students = (await detail()).roster;
  expect(students.every((s) => s.status === null)).toBe(true);
  for (const [i, status] of (["late", "absent"] as const).entries()) {
    await lead.client.mutation(api.teacher.mark_attendance, {
      ...mutation(),
      p_student_id: students[i].student_id,
      p_status: status,
      p_absence_informed: status === "absent" ? true : null,
      p_observed_marked_at: null,
      p_expected_revision: String(i),
    });
  }
  await lead.client.mutation(api.teacher.save_feedback, {
    ...mutation(),
    p_body: " Lesson reviewed ",
    p_expected_feedback_revision: "0",
  });
  const a = {
    ...mutation(),
    p_expected_revision: "2",
    p_expected_feedback_revision: "1",
  };
  await expect(
    lead.client.mutation(api.teacher.submit_lesson, a),
  ).rejects.toThrow("TP_INCOMPLETE");
  await expect(
    lead.client.mutation(api.teacher.confirm_all_present_and_submit, {
      ...a,
      p_expected_feedback_revision: "0",
    }),
  ).rejects.toThrow("TP_CONFLICT");
  expect((await detail()).roster[2].status).toBeNull();
  const receipt = await lead.client.mutation(
    api.teacher.confirm_all_present_and_submit,
    a,
  );
  expect(
    await lead.client.mutation(api.teacher.confirm_all_present_and_submit, a),
  ).toEqual({ ...receipt, replayed: true });
  expect(
    (await detail()).roster.map((s) => [s.status, s.absence_informed]),
  ).toEqual([
    ["late", null],
    ["absent", true],
    ["present", null],
  ]);
  expect(
    await t.run((ctx) => ctx.db.query("submissions").first()),
  ).toMatchObject({ revision: 3, feedbackRevision: 1 });
  expect(
    (await t.run((ctx) => ctx.db.query("notification_plans").collect())).every(
      (p) => p.status === "cancelled",
    ),
  ).toBe(true);
  await expect(
    lead.client.mutation(api.teacher.submit_lesson, {
      ...a,
      p_mutation_id: crypto.randomUUID(),
    }),
  ).rejects.toThrow("TP_LOCKED");
});
it("serializes duplicate and competing writes, including NULL clear CAS", async () => {
  const { lead, detail, mutation, t } = await fixture();
  const a = {
    ...mutation(),
    p_expected_revision: "0",
    p_student_id: (await detail()).roster[0].student_id,
    p_status: "absent" as const,
    p_absence_informed: false,
    p_observed_marked_at: null,
  };
  const results = await Promise.all([
    lead.client.mutation(api.teacher.mark_attendance, a),
    lead.client.mutation(api.teacher.mark_attendance, a),
  ]);
  expect(results.map((r) => r.replayed).sort()).toEqual([false, true]);
  await expect(
    lead.client.mutation(api.teacher.mark_attendance, {
      ...a,
      p_absence_informed: true,
    }),
  ).rejects.toThrow("TP_MUTATION_REUSED");
  const next = {
    ...a,
    ...mutation(),
    p_expected_revision: "1",
    p_status: null,
    p_absence_informed: null,
  };
  await expect(
    lead.client.mutation(api.teacher.mark_attendance, next),
  ).rejects.toThrow("TP_CONFLICT");
  const stamp = (await detail()).roster[0].marked_at;
  const race = await Promise.allSettled([
    lead.client.mutation(api.teacher.mark_attendance, {
      ...next,
      p_observed_marked_at: stamp,
    }),
    lead.client.mutation(api.teacher.mark_attendance, {
      ...next,
      ...mutation(),
      p_observed_marked_at: stamp,
    }),
  ]);
  expect(race.filter((r) => r.status === "fulfilled")).toHaveLength(1);
  expect(
    await t.run((ctx) => ctx.db.query("attendance").collect()),
  ).toHaveLength(0);
});
it("binds replay receipts to the signed-in actor", async () => {
  const { lead, admin, mutation } = await fixture();
  const a = { ...mutation(), p_expected_revision: "0" };
  await lead.client.mutation(api.teacher.mark_all_present, a);
  await expect(
    admin.client.mutation(api.teacher.mark_all_present, a),
  ).rejects.toThrow("TP_CONFLICT");
  expect(
    await admin.client.mutation(api.teacher.mark_all_present, {
      ...a,
      p_expected_revision: "1",
    }),
  ).toMatchObject({ changed_count: 0, replayed: false });
});
it("enforces start time and the seven Singapore-date teacher edit window", async () => {
  const { lead, admin, mutation, l, t } = await fixture();
  const a = { ...mutation(), p_expected_revision: "0" };
  await t.run((ctx) =>
    ctx.db.patch(l._id, { start: now + minute, end: now + 2 * minute }),
  );
  await expect(
    admin.client.mutation(api.teacher.mark_all_present, a),
  ).rejects.toThrow("TP_TOO_EARLY");
  vi.setSystemTime(now + 8 * day);
  await expect(
    lead.client.mutation(api.teacher.mark_all_present, a),
  ).rejects.toThrow("TP_TOO_OLD");
  await admin.client.mutation(api.teacher.mark_all_present, a);
});
it.each(["S1234567Z", "x".repeat(1001)])(
  "rejects sensitive or overlength feedback",
  async (body) => {
    const { lead, mutation } = await fixture();
    await expect(
      lead.client.mutation(api.teacher.save_feedback, {
        ...mutation(),
        p_expected_feedback_revision: "0",
        p_body: body,
      }),
    ).rejects.toThrow("TP_INVALID_INPUT");
  },
);
it("requires explicit admin submission of an empty roster", async () => {
  const { lead, admin, t, mutation } = await fixture();
  await t.run(async (ctx) => {
    for (const r of await ctx.db.query("lesson_roster").collect())
      await ctx.db.delete(r._id);
  });
  const a = {
    ...mutation(),
    p_expected_revision: "0",
    p_expected_feedback_revision: "0",
  };
  await expect(
    lead.client.mutation(api.teacher.submit_lesson, a),
  ).rejects.toThrow("TP_INCOMPLETE");
  expect(
    await admin.client.mutation(api.teacher.submit_lesson, a),
  ).toMatchObject({ register_revision: "0" });
});
it("supports three ten-minute snoozes and idempotent replay", async () => {
  const { lead, mutation, detail, l } = await fixture();
  await expect(
    lead.client.mutation(api.teacher.snooze_prompt, {
      ...mutation(),
      p_minutes: 15,
    }),
  ).rejects.toThrow("TP_INVALID_INPUT");
  for (let i = 1; i <= 3; i++) {
    const a = { ...mutation(), p_minutes: 10 },
      r = await lead.client.mutation(api.teacher.snooze_prompt, a);
    expect(await lead.client.mutation(api.teacher.snooze_prompt, a)).toEqual({
      ...r,
      replayed: true,
    });
    expect((await detail()).lesson.snoozed_until).toBe(
      new Date(l.end + i * 10 * minute).toISOString(),
    );
  }
  await expect(
    lead.client.mutation(api.teacher.snooze_prompt, {
      ...mutation(),
      p_minutes: 10,
    }),
  ).rejects.toThrow("TP_SNOOZE_LIMIT");
});
it("snooze and the end of class never create attendance rows", async () => {
  const { lead, mutation, t } = await fixture(6);
  await expect(
    lead.client.mutation(api.teacher.snooze_prompt, {
      ...mutation(),
      p_minutes: 10,
    }),
  ).rejects.toThrow("TP_TOO_EARLY");
  vi.setSystemTime(now + 7 * minute);
  await t.mutation(internal.queue.tick, {});
  expect(
    await t.run((ctx) => ctx.db.query("attendance").collect()),
  ).toHaveLength(0);
});
it("keeps the teacher's genuine profile and unrelated data on demo wipe", async () => {
  const { t, lead, tag } = await fixture();
  await t.mutation(internal.calendar.addStudent, {
    name: "Independent fixture",
  });
  expect(
    (await t.mutation(internal.seed.demo, { email: lead.email })).tag,
  ).toBe(tag);
  await t.mutation(internal.seed.wipeDemo, { tag });
  expect(await t.run((ctx) => ctx.db.query("students").collect())).toHaveLength(
    1,
  );
  expect(await t.run((ctx) => ctx.db.get(lead.id))).not.toBeNull();
  expect(await t.mutation(internal.seed.wipeDemo, { tag })).toEqual({
    removed: 0,
  });
});
