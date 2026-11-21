import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { dateSG, day, midnight, minute } from "./common";

export const stages = ["heads_up", "attendance", "follow_up", "final"] as const;
export const defaults = { offsets: [-5, 0, 15, 60], grace: 15, maxSnoozes: 3 };
export const policy = async (ctx: QueryCtx) =>
  (await ctx.db
    .query("prompt_policy")
    .withIndex("key", (q) => q.eq("key", "default"))
    .unique()) ?? defaults;
export function deferQuiet(ms: number) {
  const start = midnight(dateSG(ms)),
    hours = (ms - start) / (60 * minute);
  if (hours >= 22) return start + day + 9 * 60 * minute;
  if (hours < 7) return start + 9 * 60 * minute;
  return ms;
}
export const plansFor = (ctx: QueryCtx, lesson: Id<"lessons">) =>
  ctx.db
    .query("notification_plans")
    .withIndex("lesson_kind", (q) => q.eq("lesson", lesson))
    .collect();
export const boxesFor = (ctx: QueryCtx, plan: Id<"notification_plans">) =>
  ctx.db
    .query("outbox")
    .withIndex("plan_device", (q) => q.eq("plan", plan))
    .collect();
export async function cancelBox(
  ctx: MutationCtx,
  box: Doc<"outbox">,
  code: string,
) {
  if (!["pending", "claimed", "sending"].includes(box.status)) return;
  if (box.status === "sending")
    await ctx.db.insert("deliveries", {
      lesson: box.lesson,
      demo: box.demo,
      outbox: box._id,
      attempt: box.attempts,
      outcome: "unknown",
      transport: "none",
      code,
    });
  await ctx.db.patch(box._id, { status: "cancelled", lease: undefined });
}
export async function closePlan(
  ctx: MutationCtx,
  plan: Doc<"notification_plans">,
  status: "cancelled" | "superseded",
) {
  if (plan.status !== "active" && plan.status !== "pending") return;
  for (const box of await boxesFor(ctx, plan._id))
    await cancelBox(ctx, box, status);
  await ctx.db.patch(plan._id, { status });
}
export async function closePlans(ctx: MutationCtx, id: Id<"lessons">) {
  for (const plan of await plansFor(ctx, id))
    await closePlan(ctx, plan, "cancelled");
}
export async function planLesson(ctx: MutationCtx, id: Id<"lessons">) {
  const l = (await ctx.db.get(id))!;
  const c = await ctx.db.get(l.class),
    p = await ctx.db.get(l.lead);
  if (
    !c?.active ||
    c.studySpace ||
    !p?.active ||
    l.submitted !== undefined ||
    l.cancelled !== undefined
  )
    return closePlans(ctx, id);
  const config = await policy(ctx),
    existing = await plansFor(ctx, id);
  let prev = -Infinity;
  for (const [i, kind] of stages.entries()) {
    const plan = existing.find((p) => p.kind === kind);
    if (
      plan &&
      (plan.revision === l.planRevision ||
        !["pending", "active"].includes(plan.status))
    ) {
      prev = plan.due;
      continue;
    }
    const due = deferQuiet(
      Math.max(
        l.end + config.offsets[i] * minute,
        l.snoozedUntil ?? -Infinity,
        prev + 5 * minute,
      ),
    );
    prev = due;
    const fields = {
      recipient: l.lead,
      revision: l.planRevision,
      due,
      available: due,
      status: "pending" as const,
    };
    if (plan) {
      for (const box of await boxesFor(ctx, plan._id))
        await cancelBox(ctx, box, "replanned");
      await ctx.db.patch(plan._id, fields);
    } else
      await ctx.db.insert("notification_plans", {
        ...fields,
        lesson: id,
        demo: l.demo,
        kind,
      });
  }
  const overdue = prev + config.grace * minute;
  if (l.overdue !== overdue) await ctx.db.patch(id, { overdue });
}
