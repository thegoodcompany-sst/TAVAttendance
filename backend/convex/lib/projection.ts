import type { QueryCtx } from "../_generated/server";
import type { Doc, Id } from "../_generated/dataModel";
import { editError, iso, minute } from "./common";
import { plansFor, policy } from "./planner";

export const rosterFor = (ctx: QueryCtx, lesson: Id<"lessons">) =>
  ctx.db
    .query("lesson_roster")
    .withIndex("lesson_student", (q) => q.eq("lesson", lesson))
    .collect();
export const marksFor = (ctx: QueryCtx, lesson: Id<"lessons">) =>
  ctx.db
    .query("attendance")
    .withIndex("lesson_student", (q) => q.eq("lesson", lesson))
    .collect();
export const feedbackFor = (ctx: QueryCtx, lesson: Id<"lessons">) =>
  ctx.db
    .query("feedback")
    .withIndex("lesson", (q) => q.eq("lesson", lesson))
    .unique();
export async function summary(
  ctx: QueryCtx,
  l: Doc<"lessons">,
  p: Doc<"profiles">,
) {
  const [c, lead, marks, roster, plans, config] = await Promise.all([
    ctx.db.get(l.class),
    ctx.db.get(l.lead),
    marksFor(ctx, l._id),
    rosterFor(ctx, l._id),
    plansFor(ctx, l._id),
    policy(ctx),
  ]);
  const now = Date.now(),
    editable = !editError(l, p.role === "admin", now);
  const next = plans
    .filter((p) => p.status === "pending" || p.status === "active")
    .sort((a, b) => a.available - b.available)[0];
  const state =
    l.cancelled !== undefined
      ? "cancelled"
      : l.submitted !== undefined
        ? "submitted"
        : now >= l.overdue
          ? "overdue"
          : now >= l.end
            ? "awaiting_attendance"
            : now >= l.start
              ? "in_progress"
              : "scheduled";
  return {
    lesson_id: l.uuid,
    class_id: c!.uuid,
    class_label: c!.label,
    scheduled_start_at: iso(l.start),
    scheduled_end_at: iso(l.end),
    state,
    accountable_teacher_id: lead!.uuid,
    accountable_teacher_label: lead!.name,
    is_accountable: l.lead === p._id,
    register_revision: String(l.revision),
    roster_count: roster.length,
    marked_count: marks.length,
    submitted_at: l.submitted === undefined ? null : iso(l.submitted),
    next_prompt_at: next ? iso(next.available) : null,
    snoozed_until: l.snoozedUntil === undefined ? null : iso(l.snoozedUntil),
    overdue_at: iso(l.overdue),
    can_edit: editable,
    can_submit:
      editable &&
      marks.length === roster.length &&
      (roster.length > 0 || p.role === "admin"),
    can_snooze:
      editable &&
      !!next &&
      now >= l.end - 5 * minute &&
      l.snoozes < config.maxSnoozes &&
      Math.max(now, l.snoozedUntil ?? 0) < l.end + 60 * minute,
  };
}
