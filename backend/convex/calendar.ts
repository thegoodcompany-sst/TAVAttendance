import { v } from "convex/values";
import {
  internalMutation,
  mutation,
  query,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import {
  actor,
  dateSG,
  day,
  fail,
  iso,
  midnight,
  minute,
  review,
  uuid,
} from "./lib/common";
import { closePlans, planLesson, plansFor } from "./lib/planner";
import { feedbackFor, marksFor, rosterFor, summary } from "./lib/projection";

function range(from: string, until: string) {
  if (midnight(until) < midnight(from)) fail("TP_INVALID_INPUT");
}
export const addTerm = internalMutation({
  args: { label: v.string(), from: v.string(), until: v.string() },
  handler: (ctx, a) => {
    range(a.from, a.until);
    return ctx.db.insert("terms", a);
  },
});
export const addClass = internalMutation({
  args: { label: v.string(), subject: v.string(), studySpace: v.boolean() },
  handler: async (ctx, a) => {
    if (
      !a.label.trim() ||
      a.label.trim().length > 80 ||
      (await ctx.db
        .query("classes")
        .withIndex("label", (q) => q.eq("label", a.label.trim()))
        .unique())
    )
      fail("TP_INVALID_INPUT");
    return ctx.db.insert("classes", {
      ...a,
      label: a.label.trim(),
      active: true,
      uuid: crypto.randomUUID(),
    });
  },
});
export const addStudent = internalMutation({
  args: { name: v.string() },
  handler: (ctx, a) => {
    if (!a.name.trim() || a.name.trim().length > 80) fail("TP_INVALID_INPUT");
    return ctx.db.insert("students", {
      uuid: crypto.randomUUID(),
      name: a.name.trim(),
      active: true,
    });
  },
});
export const enroll = internalMutation({
  args: {
    student: v.id("students"),
    class: v.id("classes"),
    from: v.string(),
    until: v.optional(v.string()),
  },
  handler: async (ctx, a) => {
    range(a.from, a.until ?? a.from);
    if (!(await ctx.db.get(a.student)) || !(await ctx.db.get(a.class)))
      fail("TP_INVALID_INPUT");
    const rows = await ctx.db
      .query("enrollments")
      .withIndex("pair", (q) => q.eq("class", a.class).eq("student", a.student))
      .collect();
    if (
      rows.some(
        (r) => r.from <= (a.until ?? "9999") && a.from <= (r.until ?? "9999"),
      )
    )
      fail("TP_CONFLICT");
    return ctx.db.insert("enrollments", a);
  },
});
export const setRule = internalMutation({
  args: {
    id: v.optional(v.id("timetable_rules")),
    class: v.id("classes"),
    term: v.id("terms"),
    teacher: v.id("profiles"),
    weekday: v.number(),
    start: v.string(),
    minutes: v.number(),
    from: v.string(),
    until: v.string(),
    active: v.boolean(),
  },
  handler: async (ctx, { id, ...a }) => {
    range(a.from, a.until);
    const term = await ctx.db.get(a.term),
      p = await ctx.db.get(a.teacher);
    if (
      !term ||
      !(await ctx.db.get(a.class)) ||
      !p ||
      (a.active && (!p.active || p.role !== "teacher")) ||
      a.from < term.from ||
      a.until > term.until ||
      !Number.isInteger(a.weekday) ||
      a.weekday < 1 ||
      a.weekday > 7 ||
      !/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(a.start) ||
      !Number.isInteger(a.minutes) ||
      a.minutes < 15 ||
      a.minutes > 240
    )
      fail("TP_INVALID_INPUT");
    if (id) {
      if ((await ctx.db.get(id))?.class !== a.class) fail("TP_INVALID_INPUT");
      await ctx.db.patch(id, a);
      return id;
    }
    return ctx.db.insert("timetable_rules", a);
  },
});
export const addClosure = internalMutation({
  args: {
    class: v.optional(v.id("classes")),
    from: v.string(),
    until: v.string(),
    reason: v.union(v.literal("public_holiday"), v.literal("centre_closed")),
  },
  handler: async (ctx, a) => {
    range(a.from, a.until);
    if (a.class && !(await ctx.db.get(a.class))) fail("TP_INVALID_INPUT");
    return ctx.db.insert("calendar_exceptions", a);
  },
});
async function closure(ctx: QueryCtx, c: Id<"classes">, date: string) {
  const reasons = [];
  for (const scope of [undefined, c]) {
    const rows = await ctx.db
      .query("calendar_exceptions")
      .withIndex("class_until", (q) => q.eq("class", scope).gte("until", date))
      .collect();
    reasons.push(...rows.filter((r) => r.from <= date).map((r) => r.reason));
  }
  return reasons.includes("public_holiday") ? "public_holiday" : reasons[0];
}
async function refreshRoster(
  ctx: MutationCtx,
  l: Doc<"lessons">,
  initial = false,
) {
  const date = dateSG(l.start),
    existing = await rosterFor(ctx, l._id);
  const enrolled = await ctx.db
    .query("enrollments")
    .withIndex("class_from", (q) => q.eq("class", l.class).lte("from", date))
    .collect();
  const eligible = new Map<Id<"students">, Id<"enrollments">>();
  for (const e of enrolled)
    if ((!e.until || e.until >= date) && (await ctx.db.get(e.student))?.active)
      eligible.set(e.student, e._id);
  let changed = false;
  for (const r of existing) {
    if (!eligible.has(r.student)) {
      await ctx.db.delete(r._id);
      changed = true;
    } else {
      if (r.enrollment !== eligible.get(r.student))
        await ctx.db.patch(r._id, { enrollment: eligible.get(r.student)! });
      eligible.delete(r.student);
    }
  }
  for (const [student, enrollment] of eligible) {
    await ctx.db.insert("lesson_roster", {
      lesson: l._id,
      student,
      enrollment,
      demo: l.demo,
    });
    changed = true;
  }
  if (changed && !initial)
    await ctx.db.patch(l._id, { revision: l.revision + 1 });
  return changed;
}
async function conflictCheck(ctx: QueryCtx, l: Doc<"lessons">) {
  const near = await ctx.db
    .query("lessons")
    .withIndex("class_start", (q) =>
      q
        .eq("class", l.class)
        .gt("start", l.start - 240 * minute)
        .lt("start", l.end),
    )
    .collect();
  if (
    near.some(
      (r) => r._id !== l._id && r.cancelled === undefined && r.end > l.start,
    )
  )
    fail("TP_CONFLICT");
}
export async function createLesson(
  ctx: MutationCtx,
  fields: Pick<
    Doc<"lessons">,
    | "class"
    | "rule"
    | "occurrence"
    | "start"
    | "end"
    | "lead"
    | "demo"
    | "reason"
  >,
) {
  const p = await ctx.db.get(fields.lead);
  if (
    !p?.active ||
    p.role !== "teacher" ||
    !(fields.end > fields.start && fields.end - fields.start <= 240 * minute)
  )
    fail("TP_INVALID_INPUT");
  const id = await ctx.db.insert("lessons", {
    ...fields,
    uuid: crypto.randomUUID(),
    revision: 0,
    planRevision: 1,
    snoozes: 0,
    overdue: fields.end + 75 * minute,
    cancelled: fields.reason ? Date.now() : undefined,
  });
  await ctx.db.insert("lesson_staff", {
    lesson: id,
    teacher: fields.lead,
    assignment: "regular",
    demo: fields.demo,
  });
  await refreshRoster(ctx, (await ctx.db.get(id))!, true);
  await planLesson(ctx, id);
  return id;
}
async function swapLead(
  ctx: MutationCtx,
  l: Doc<"lessons">,
  teacher: Id<"profiles">,
  keep: boolean,
  assignment: "regular" | "substitute",
) {
  if (l.lead === teacher) return;
  const p = await ctx.db.get(teacher);
  if (!p?.active || p.role !== "teacher") fail("TP_INVALID_INPUT");
  const rows = await ctx.db
    .query("lesson_staff")
    .withIndex("lesson_teacher", (q) => q.eq("lesson", l._id))
    .collect();
  const old = rows.find((r) => r.teacher === l.lead)!,
    next = rows.find((r) => r.teacher === teacher);
  if (keep) await ctx.db.patch(old._id, { assignment: "assistant" });
  else await ctx.db.delete(old._id);
  if (next) await ctx.db.patch(next._id, { assignment });
  else
    await ctx.db.insert("lesson_staff", {
      lesson: l._id,
      teacher,
      assignment,
      demo: l.demo,
    });
  await ctx.db.patch(l._id, {
    lead: teacher,
    substituted: assignment === "substitute",
    planRevision: l.planRevision + 1,
  });
}
async function cancel(ctx: MutationCtx, l: Doc<"lessons">, reason: string) {
  await ctx.db.patch(l._id, { cancelled: Date.now(), reason });
  await closePlans(ctx, l._id);
}
const worked = async (ctx: QueryCtx, l: Doc<"lessons">) =>
  l.start <= Date.now() ||
  l.submitted !== undefined ||
  !!(await marksFor(ctx, l._id)).length ||
  !!(await feedbackFor(ctx, l._id));
export const generate_lessons = internalMutation({
  args: { from: v.optional(v.string()), until: v.optional(v.string()) },
  handler: async (ctx, a) => {
    const from = a.from ?? dateSG(Date.now()),
      until = a.until ?? dateSG(midnight(from) + 42 * day);
    range(from, until);
    if (midnight(until) - midnight(from) >= 92 * day) fail("TP_INVALID_INPUT");
    const counts = {
      created: 0,
      updated: 0,
      cancelled: 0,
      unchanged: 0,
      staffing_skipped: 0,
    };
    const check = new Set<Id<"lessons">>();
    for (const rule of await ctx.db.query("timetable_rules").collect()) {
      const c = await ctx.db.get(rule.class),
        teacher = await ctx.db.get(rule.teacher);
      if (rule.active && (!teacher?.active || teacher.role !== "teacher")) {
        counts.staffing_skipped++;
        await ctx.db.insert("audit_events", {
          event: "calendar_staffing_unresolved",
          demo: rule.demo,
        });
        continue;
      }
      const occurrences = await ctx.db
        .query("lessons")
        .withIndex("rule_date", (q) =>
          q
            .eq("rule", rule._id)
            .gte("occurrence", from)
            .lte("occurrence", until),
        )
        .collect();
      // A moved lesson can enter this batch from an earlier occurrence.
      const moved = await ctx.db
        .query("lessons")
        .withIndex("class_start", (q) =>
          q
            .eq("class", rule.class)
            .gte("start", midnight(from))
            .lt("start", midnight(until) + day),
        )
        .collect();
      const prior = new Map(
        [
          ...occurrences,
          ...moved.filter((l) => l.rule === rule._id && l.moved),
        ].map((l) => [l.occurrence, l]),
      );
      const dates = new Set(prior.keys());
      for (let ms = midnight(from); ms <= midnight(until); ms += day)
        dates.add(dateSG(ms));
      for (const d of dates) {
        const l = prior.get(d);
        const matches =
          rule.active &&
          c?.active &&
          d >= rule.from &&
          d <= rule.until &&
          (new Date(d + "T12:00:00Z").getUTCDay() || 7) === rule.weekday;
        if (!matches && !l) continue;
        const start = l?.moved
            ? l.start
            : Date.parse(d + "T" + rule.start + "+08:00"),
          end = l?.moved ? l.end : start + rule.minutes * minute;
        const reason = matches
          ? await closure(ctx, rule.class, dateSG(start))
          : "rule_removed";
        if (!l) {
          const id = await createLesson(ctx, {
            class: rule.class,
            rule: rule._id,
            occurrence: d,
            start,
            end,
            reason,
            lead: rule.teacher,
            demo: rule.demo,
          });
          if (!reason) check.add(id);
          counts.created++;
          continue;
        }
        if (l.cancelled !== undefined) {
          counts.unchanged++;
          continue;
        }
        const staffing = !l.substituted && rule.teacher !== l.lead,
          timing = start !== l.start || end !== l.end;
        if (await worked(ctx, l)) {
          if (reason || timing || staffing)
            await ctx.db.insert("audit_events", {
              event: "calendar_work_preserved",
              lesson: l._id,
              demo: l.demo,
            });
          counts.unchanged++;
          continue;
        }
        if (reason) {
          await cancel(ctx, l, reason);
          counts.cancelled++;
          continue;
        }
        if (staffing) await swapLead(ctx, l, rule.teacher, false, "regular");
        if (timing)
          await ctx.db.patch(l._id, {
            start,
            end,
            planRevision: l.planRevision + 1,
          });
        const current = (await ctx.db.get(l._id))!,
          rosterChanged = await refreshRoster(ctx, current);
        if (timing || staffing || rosterChanged) {
          check.add(l._id);
          await planLesson(ctx, l._id);
          counts.updated++;
        } else counts.unchanged++;
      }
    }
    for (const id of check) await conflictCheck(ctx, (await ctx.db.get(id))!);
    return counts;
  },
});
async function adminLesson(ctx: MutationCtx, id: string) {
  const { l, p } = await review(ctx, id);
  if (p.role !== "admin") fail("TP_NOT_AVAILABLE");
  if (l.submitted !== undefined) fail("TP_LOCKED");
  return { l, p };
}
async function changed(
  ctx: MutationCtx,
  l: Doc<"lessons">,
  p: Doc<"profiles">,
  event: string,
) {
  await ctx.db.insert("audit_events", {
    event,
    lesson: l._id,
    actor: p._id,
    demo: l.demo,
  });
  return summary(ctx, (await ctx.db.get(l._id))!, p);
}
export const cancel_lesson = mutation({
  args: { p_lesson_id: v.string() },
  handler: async (ctx, a) => {
    const { l, p } = await adminLesson(ctx, a.p_lesson_id);
    if (l.cancelled !== undefined) return summary(ctx, l, p);
    await cancel(ctx, l, "manual");
    return changed(ctx, l, p, "cancel_lesson");
  },
});
export const assign_lesson_teacher = mutation({
  args: {
    p_lesson_id: v.string(),
    p_teacher_id: v.string(),
    p_keep_previous_as_assistant: v.boolean(),
  },
  handler: async (ctx, a) => {
    const { l, p } = await adminLesson(ctx, a.p_lesson_id);
    if (l.cancelled !== undefined) fail("TP_LOCKED");
    const teacher = await ctx.db
      .query("profiles")
      .withIndex("uuid", (q) => q.eq("uuid", uuid(a.p_teacher_id)))
      .unique();
    if (!teacher?.active || teacher.role !== "teacher")
      fail("TP_INVALID_INPUT");
    await swapLead(
      ctx,
      l,
      teacher._id,
      a.p_keep_previous_as_assistant,
      "substitute",
    );
    await planLesson(ctx, l._id);
    return changed(ctx, l, p, "assign_lesson_teacher");
  },
});
export const edit_lesson = mutation({
  args: {
    p_lesson_id: v.string(),
    p_start_at: v.string(),
    p_end_at: v.string(),
  },
  handler: async (ctx, a) => {
    const { l, p } = await adminLesson(ctx, a.p_lesson_id);
    if (l.cancelled !== undefined || (await worked(ctx, l))) fail("TP_LOCKED");
    const start = Date.parse(a.p_start_at),
      end = Date.parse(a.p_end_at);
    if (
      !Number.isFinite(start) ||
      !Number.isFinite(end) ||
      start <= Date.now() ||
      end <= start ||
      end - start > 240 * minute ||
      (await closure(ctx, l.class, dateSG(start)))
    )
      fail("TP_INVALID_INPUT");
    const next = { ...l, start, end };
    await conflictCheck(ctx, next);
    await ctx.db.patch(l._id, {
      start,
      end,
      moved: true,
      planRevision: l.planRevision + 1,
    });
    await refreshRoster(ctx, next);
    await planLesson(ctx, l._id);
    return changed(ctx, l, p, "edit_lesson");
  },
});
export const admin_missing_submissions = query({
  args: { p_from: v.string(), p_until: v.string() },
  handler: async (ctx, a) => {
    const p = await actor(ctx);
    if (p.role !== "admin") fail("TP_NOT_AVAILABLE");
    range(a.p_from, a.p_until);
    const from = midnight(a.p_from),
      until = midnight(a.p_until) + day;
    if (until - from > 92 * day) fail("TP_INVALID_INPUT");
    const lessons = [];
    for (const l of await ctx.db
      .query("lessons")
      .withIndex("start", (q) => q.gte("start", from).lt("start", until))
      .collect()) {
      if (
        l.cancelled !== undefined ||
        l.submitted !== undefined ||
        l.end > Date.now() ||
        (await ctx.db.get(l.class))?.studySpace !== false
      )
        continue;
      const logs = await ctx.db
        .query("deliveries")
        .withIndex("lesson", (q) => q.eq("lesson", l._id))
        .order("desc")
        .first();
      const plans = await plansFor(ctx, l._id);
      const active = plans.some((plan) => plan.status === "active");
      lessons.push({
        ...(await summary(ctx, l, p)),
        delivery_state: active
          ? "pending"
          : !logs
            ? "not_attempted"
            : logs.outcome === "accepted"
              ? "accepted"
              : logs.outcome === "no_devices"
                ? "no_devices"
                : "failed",
        last_attempt_at: logs ? iso(logs._creationTime) : null,
      });
    }
    return {
      server_now: iso(Date.now()),
      from: a.p_from,
      until: a.p_until,
      lessons,
    };
  },
});
