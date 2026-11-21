import { afterEach, expect, it, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { fixture } from "../tests/fixture";
import { iso, minute } from "./lib/common";

afterEach(() => vi.useRealTimers());
async function calendar() {
  const f = await fixture();
  const c = await f.t.mutation(internal.calendar.addClass, {
    label: "Calendar class",
    subject: "English",
    studySpace: false,
  });
  const dates = { from: "2027-01-01", until: "2027-01-31" };
  const term = await f.t.mutation(internal.calendar.addTerm, {
    ...dates,
    label: "January",
  });
  const rule = {
    ...dates,
    class: c,
    term,
    teacher: f.lead.id,
    weekday: 1,
    start: "19:00:00",
    minutes: 120,
    active: true,
  };
  const id = await f.t.mutation(internal.calendar.setRule, rule);
  const generate = (from = "2027-01-11", until = from) =>
    f.t.mutation(internal.calendar.generate_lessons, { from, until });
  const lesson = () =>
    f.t.run((ctx) =>
      ctx.db
        .query("lessons")
        .withIndex("rule_date", (q) => q.eq("rule", id))
        .first(),
    );
  return { ...f, c, rule, id, generate, lesson };
}
it("uses rule and original occurrence date as the unique key across concurrent generation", async () => {
  const { t, generate, lesson, id, c, rule } = await calendar();
  await t.mutation(internal.calendar.setRule, { ...rule, start: "17:00" });
  const counts = await Promise.all([generate(), generate()]);
  expect(counts.reduce((n, r) => n + r.created, 0)).toBe(2);
  const rows = await t.run((ctx) =>
    ctx.db
      .query("lessons")
      .withIndex("class_start", (q) => q.eq("class", c))
      .collect(),
  );
  expect(rows.map((l) => l.occurrence)).toEqual(["2027-01-11", "2027-01-11"]);
  expect((await lesson())!.rule).toBe(id);
  expect(new Set(rows.map((r) => r.uuid)).size).toBe(2);
});
it("rolls back the whole generation batch for a final class overlap", async () => {
  const { t, rule, generate, lesson } = await calendar();
  await t.mutation(internal.calendar.setRule, { ...rule, start: "20:59" });
  await expect(generate()).rejects.toThrow("TP_CONFLICT");
  expect(await lesson()).toBeNull();
});
it("checks closures and membership on a moved lesson's actual Singapore date", async () => {
  const { t, c, generate, admin, lesson } = await calendar();
  const student = await t.mutation(internal.calendar.addStudent, {
    name: "Calendar fixture",
  });
  await t.mutation(internal.calendar.enroll, {
    class: c,
    student,
    from: "2027-01-12",
    until: "2027-01-12",
  });
  await generate();
  const original = (await lesson())!,
    target = { p_lesson_id: original.uuid };
  const moved = await admin.client.mutation(api.calendar.edit_lesson, {
    ...target,
    p_start_at: "2027-01-12T19:00:00+08:00",
    p_end_at: "2027-01-12T21:00:00+08:00",
  });
  expect(moved.roster_count).toBe(1);
  expect(moved.register_revision).toBe("1");
  await t.mutation(internal.calendar.addClosure, {
    class: c,
    from: "2027-01-11",
    until: "2027-01-11",
    reason: "centre_closed",
  });
  await generate();
  expect((await lesson())!.cancelled).toBeUndefined();
  await t.mutation(internal.calendar.addClosure, {
    from: "2027-01-12",
    until: "2027-01-12",
    reason: "public_holiday",
  });
  await generate("2027-01-12");
  expect(await lesson()).toMatchObject({
    uuid: original.uuid,
    occurrence: "2027-01-11",
    reason: "public_holiday",
  });
  expect(
    (await admin.client.query(api.teacher.lesson_for_prompt, target)).lesson,
  ).toMatchObject({
    state: "cancelled",
    can_edit: false,
    next_prompt_at: null,
  });
});
it("rejects moving onto a closure and preserves the original schedule", async () => {
  const { t, admin, generate, lesson } = await calendar();
  await generate();
  const l = (await lesson())!;
  await t.mutation(internal.calendar.addClosure, {
    from: "2027-01-12",
    until: "2027-01-12",
    reason: "centre_closed",
  });
  await expect(
    admin.client.mutation(api.calendar.edit_lesson, {
      p_lesson_id: l.uuid,
      p_start_at: iso(l.start + 1440 * minute),
      p_end_at: iso(l.end + 1440 * minute),
    }),
  ).rejects.toThrow("TP_INVALID_INPUT");
  expect((await lesson())!.start).toBe(l.start);
});
it("does not resurrect retired occurrences after a rule is reactivated", async () => {
  const { t, id, rule, generate, lesson } = await calendar();
  await generate();
  await t.mutation(internal.calendar.setRule, { ...rule, id, active: false });
  await generate();
  expect((await lesson())!.reason).toBe("rule_removed");
  await t.mutation(internal.calendar.setRule, { ...rule, id, active: true });
  await generate();
  expect((await lesson())!.cancelled).toBeDefined();
});
it("preserves exactly one active accountable teacher on rule and profile changes", async () => {
  const { t, lead, admin, rule, generate, lesson } = await calendar();
  await expect(
    t.mutation(internal.calendar.setRule, { ...rule, teacher: admin.id }),
  ).rejects.toThrow("TP_INVALID_INPUT");
  await expect(
    t.mutation(internal.staff.setAccess, {
      profile: lead.id,
      role: "admin",
      active: true,
    }),
  ).rejects.toThrow("TP_CONFLICT");
  await generate();
  const l = (await lesson())!;
  const staff = await t.run((ctx) =>
    ctx.db
      .query("lesson_staff")
      .withIndex("lesson_teacher", (q) => q.eq("lesson", l._id))
      .collect(),
  );
  expect(staff.map((s) => s.teacher)).toEqual([l.lead]);
});
it("validates inclusive enrollment dates and term/rule bounds", async () => {
  const { t, rule, c } = await calendar();
  const student = await t.mutation(internal.calendar.addStudent, {
    name: "Test member",
  });
  await t.mutation(internal.calendar.enroll, {
    student,
    class: c,
    from: "2027-01-01",
    until: "2027-01-11",
  });
  await expect(
    t.mutation(internal.calendar.enroll, {
      student,
      class: c,
      from: "2027-01-11",
    }),
  ).rejects.toThrow("TP_CONFLICT");
  await expect(
    t.mutation(internal.calendar.setRule, { ...rule, until: "2027-02-01" }),
  ).rejects.toThrow("TP_INVALID_INPUT");
});
it("replans pending stages on policy updates and rejects invalid limits", async () => {
  const { t, l } = await fixture();
  await expect(
    t.mutation(internal.settings.updatePolicy, {
      offsets: [-5, 0, 15, 60],
      grace: 15,
      maxSnoozes: 4,
    }),
  ).rejects.toThrow("TP_INVALID_INPUT");
  await t.mutation(internal.settings.updatePolicy, {
    offsets: [-5, 0, 15, 60],
    grace: 20,
    maxSnoozes: 2,
  });
  expect((await t.run((ctx) => ctx.db.get(l._id)))!.overdue - l.overdue).toBe(
    5 * minute,
  );
});
