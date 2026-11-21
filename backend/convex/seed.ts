import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { createLesson } from "./calendar";
import { dateSG, emailKey, fail, minute, uuid } from "./lib/common";

export const demo = internalMutation({
  args: { email: v.string(), minutes: v.optional(v.number()) },
  handler: async (ctx, a) => {
    if (
      !(
        await ctx.db
          .query("runtime_settings")
          .withIndex("key", (q) => q.eq("key", "default"))
          .unique()
      )?.demoEnabled
    )
      fail("TP_DISABLED");
    const email = emailKey(a.email),
      p = await ctx.db
        .query("profiles")
        .withIndex("email", (q) => q.eq("email", email))
        .unique();
    if (!p?.active || p.role !== "teacher") fail("TP_NOT_AVAILABLE");
    const minutes = a.minutes ?? 6;
    if (!Number.isInteger(minutes) || minutes < 0 || minutes > 120)
      fail("TP_INVALID_INPUT");
    const tag = p.uuid,
      prior = await ctx.db
        .query("lessons")
        .withIndex("demo", (q) => q.eq("demo", tag))
        .first();
    if (prior) return { tag, lesson_id: prior.uuid };
    const end = Date.now() + minutes * minute,
      start = end - 120 * minute,
      occurrence = dateSG(start);
    const c = await ctx.db.insert("classes", {
      demo: tag,
      uuid: crypto.randomUUID(),
      label: "Demo English " + tag.slice(0, 8),
      subject: "English",
      active: true,
      studySpace: false,
    });
    for (const name of ["Demo Student A", "Demo Student B", "Demo Student C"]) {
      const student = await ctx.db.insert("students", {
        demo: tag,
        uuid: crypto.randomUUID(),
        name,
        active: true,
      });
      await ctx.db.insert("enrollments", {
        demo: tag,
        class: c,
        student,
        from: occurrence,
      });
    }
    const id = await createLesson(ctx, {
      demo: tag,
      class: c,
      occurrence,
      start,
      end,
      lead: p._id,
    });
    return { tag, lesson_id: (await ctx.db.get(id))!.uuid };
  },
});
export const wipeDemo = internalMutation({
  args: { tag: v.string() },
  handler: async (ctx, { tag }) => {
    const key = uuid(tag);
    let removed = 0;
    for (const table of [
      "deliveries",
      "outbox",
      "notification_plans",
      "audit_events",
      "mutation_receipts",
      "submissions",
      "feedback",
      "attendance",
      "lesson_staff",
      "lesson_roster",
      "lessons",
      "enrollments",
      "students",
      "timetable_rules",
      "calendar_exceptions",
      "terms",
      "classes",
    ] as const) {
      const rows = await ctx.db
        .query(table)
        .withIndex("demo", (q) => q.eq("demo", key))
        .collect();
      for (const row of rows) {
        await ctx.db.delete(row._id);
        removed++;
      }
    }
    return { removed };
  },
});
