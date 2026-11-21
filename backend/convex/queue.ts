import { v } from "convex/values";
import { internalMutation, type MutationCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import { day, editError, flag, iso, minute } from "./lib/common";
import {
  boxesFor,
  cancelBox,
  closePlan,
  deferQuiet,
  plansFor,
  stages,
} from "./lib/planner";
import type { Delivery } from "./lib/push/prompt_dispatch";

const leaseArgs = { id: v.id("outbox"), lease: v.string() };
async function eligible(
  ctx: MutationCtx,
  p: Doc<"notification_plans">,
  now: number,
) {
  const l = (await ctx.db.get(p.lesson))!,
    c = await ctx.db.get(l.class),
    teacher = await ctx.db.get(p.recipient);
  if (
    !c?.active ||
    c.studySpace ||
    !teacher?.active ||
    l.lead !== p.recipient ||
    l.planRevision !== p.revision ||
    l.cancelled !== undefined ||
    l.submitted !== undefined ||
    editError(l, false, now) === "TP_TOO_OLD"
  ) {
    await closePlan(ctx, p, "cancelled");
    return null;
  }
  const later = (await plansFor(ctx, l._id)).filter(
    (n) => stages.indexOf(n.kind) > stages.indexOf(p.kind),
  );
  if (
    (p.kind === "heads_up" && now >= l.end) ||
    later.some((n) => n.due <= now)
  ) {
    await closePlan(ctx, p, "superseded");
    return null;
  }
  return {
    l,
    expires: Math.min(
      now + 60 * minute,
      ...later.map((n) => n.due),
      p.kind === "heads_up" ? l.end : Infinity,
    ),
  };
}
async function complete(ctx: MutationCtx, p: Doc<"notification_plans">) {
  if (p.status !== "active") return;
  if (
    !(await boxesFor(ctx, p._id)).some(
      (b) =>
        b.revision === p.revision &&
        ["pending", "claimed", "sending"].includes(b.status),
    )
  )
    await ctx.db.patch(p._id, { status: "completed" });
}
async function materialize(
  ctx: MutationCtx,
  p: Doc<"notification_plans">,
  now: number,
) {
  const current = await eligible(ctx, p, now);
  if (!current) return;
  const available = deferQuiet(Math.max(current.l.start, now));
  if (available > now) {
    await ctx.db.patch(p._id, { available });
    return;
  }
  const devices = await ctx.db
    .query("teacher_devices")
    .withIndex("active", (q) =>
      q
        .eq("owner", p.recipient)
        .eq("revoked", undefined)
        .gte("seen", now - 90 * day),
    )
    .order("desc")
    .take(5);
  const prior = await boxesFor(ctx, p._id);
  for (const device of devices.length ? devices : [null]) {
    const fields = {
      plan: p._id,
      revision: p.revision,
      device: device?._id,
      recipient: p.recipient,
      lesson: p.lesson,
      demo: p.demo,
      available: now,
    };
    const existing = prior.find((b) => b.device === device?._id);
    if (existing) {
      if (
        existing.status === "cancelled" &&
        existing.attempts < 3 &&
        existing.deviceSeen === undefined &&
        device
      )
        await ctx.db.patch(existing._id, { ...fields, status: "pending" });
      continue;
    }
    const id = await ctx.db.insert("outbox", {
      ...fields,
      uuid: crypto.randomUUID(),
      attempts: device ? 0 : 1,
      status: device ? "pending" : "failed",
    });
    if (!device)
      await ctx.db.insert("deliveries", {
        lesson: p.lesson,
        demo: p.demo,
        outbox: id,
        attempt: 1,
        outcome: "no_devices",
        transport: "none",
      });
  }
  await ctx.db.patch(p._id, { status: "active" });
  await complete(ctx, { ...p, status: "active" });
}
async function checkBox(ctx: MutationCtx, b: Doc<"outbox">, now: number) {
  const p = (await ctx.db.get(b.plan))!;
  if (p.status !== "active" || b.revision !== p.revision) {
    await cancelBox(ctx, b, "replanned");
    return null;
  }
  const current = await eligible(ctx, p, now);
  if (!current) return null;
  const device = b.device ? await ctx.db.get(b.device) : null;
  if (
    !device ||
    device.revoked !== undefined ||
    device.owner !== p.recipient ||
    device.seen < now - 90 * day
  ) {
    await cancelBox(ctx, b, "revoked");
    await complete(ctx, p);
    return null;
  }
  const allowed = deferQuiet(Math.max(now, current.l.start));
  if (allowed > now) {
    await ctx.db.patch(b._id, {
      status: "pending",
      lease: undefined,
      available: allowed,
    });
    return null;
  }
  return { ...current, p, device };
}
export const tick = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    // Expired sends have an ambiguous provider outcome. Never repeat such a send.
    for (const status of ["claimed", "sending"] as const) {
      const rows = await ctx.db
        .query("outbox")
        .withIndex("status_available", (q) =>
          q.eq("status", status).lte("available", now),
        )
        .take(40);
      for (const b of rows) {
        if (status === "claimed")
          await ctx.db.patch(b._id, {
            status: "pending",
            lease: undefined,
            available: now,
          });
        else {
          await cancelBox(ctx, b, "lease_expired");
          await complete(ctx, (await ctx.db.get(b.plan))!);
        }
      }
    }
    if (!(await flag(ctx, "teacher_prompts"))) return 0;
    if (
      process.env.APNS_DRY_RUN === "false" &&
      !(await flag(ctx, "teacher_prompt_push"))
    )
      return 0;
    const due = await ctx.db
      .query("notification_plans")
      .withIndex("status_available", (q) =>
        q.eq("status", "pending").lte("available", now),
      )
      .take(30);
    for (const p of due) await materialize(ctx, p, now);
    const pending = await ctx.db
      .query("outbox")
      .withIndex("status_available", (q) =>
        q.eq("status", "pending").lte("available", now),
      )
      .take(40);
    let claimed = 0;
    for (const b of pending) {
      if (!(await checkBox(ctx, b, now))) continue;
      const lease = crypto.randomUUID();
      await ctx.db.patch(b._id, {
        status: "claimed",
        lease,
        available: now + 2 * minute,
      });
      await ctx.scheduler.runAfter(0, internal.push.send, { id: b._id, lease });
      claimed++;
    }
    return claimed;
  },
});
export const prepare = internalMutation({
  args: leaseArgs,
  handler: async (ctx, { id, lease }): Promise<Delivery | null> => {
    const now = Date.now(),
      b = await ctx.db.get(id);
    if (!b || b.lease !== lease || b.status !== "claimed" || b.available <= now)
      return null;
    if (
      !(await flag(ctx, "teacher_prompts")) ||
      (process.env.APNS_DRY_RUN === "false" &&
        !(await flag(ctx, "teacher_prompt_push")))
    ) {
      await ctx.db.patch(id, {
        status: "pending",
        lease: undefined,
        available: now + minute,
      });
      return null;
    }
    const state = await checkBox(ctx, b, now);
    if (!state) return null;
    const { l, p, device, expires } = state;
    const dry = l.demo !== undefined || process.env.APNS_DRY_RUN !== "false";
    await ctx.db.patch(id, {
      status: "sending",
      deviceSeen: device.seen,
      attempts: b.attempts + 1,
    });
    return {
      mode: dry ? "dry_run" : "apns",
      outbox_id: b.uuid,
      lesson_id: l.uuid,
      kind: p.kind,
      token: device.token,
      environment: device.environment,
      collapse_id: "tp:" + l.uuid,
      thread_id: "teacher-lesson:" + l.uuid,
      expires_at: iso(expires),
    };
  },
});
const resultValidator = v.union(
  v.object({
    accepted: v.literal(true),
    provider_id: v.string(),
    transport: v.union(v.literal("apns"), v.literal("dry_run")),
  }),
  v.object({
    accepted: v.literal(false),
    error_code: v.string(),
    retryable: v.boolean(),
    invalidate_device: v.boolean(),
  }),
);
export const finish = internalMutation({
  args: { ...leaseArgs, result: resultValidator },
  handler: async (ctx, { id, lease, result: r }) => {
    const now = Date.now(),
      b = await ctx.db.get(id);
    if (!b || b.status !== "sending" || b.lease !== lease || b.available <= now)
      return false;
    const ambiguous =
      !r.accepted && ["timeout", "transport_error"].includes(r.error_code);
    const retry = !r.accepted && !ambiguous && r.retryable && b.attempts < 3;
    await ctx.db.insert("deliveries", {
      lesson: b.lesson,
      demo: b.demo,
      outbox: id,
      attempt: b.attempts,
      transport: r.accepted ? r.transport : "apns",
      outcome: r.accepted
        ? "accepted"
        : ambiguous
          ? "unknown"
          : retry
            ? "retry"
            : "permanent_failure",
      code: r.accepted ? undefined : r.error_code,
      provider: r.accepted ? r.provider_id : undefined,
    });
    if (
      !r.accepted &&
      r.invalidate_device &&
      ["bad_device_token", "unregistered"].includes(r.error_code) &&
      b.device
    ) {
      const d = await ctx.db.get(b.device);
      if (d && d.seen === b.deviceSeen && d.revoked === undefined)
        await ctx.db.patch(d._id, { revoked: now });
    }
    await ctx.db.patch(id, {
      lease: undefined,
      status: r.accepted ? "sent" : retry ? "pending" : "failed",
      deviceSeen: retry ? undefined : b.deviceSeen,
      available: retry
        ? deferQuiet(now + (b.attempts === 1 ? 1 : 5) * minute)
        : now,
    });
    await complete(ctx, (await ctx.db.get(b.plan))!);
    return true;
  },
});
