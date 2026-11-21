import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { fail } from "./lib/common";
import { defaults, planLesson } from "./lib/planner";
export const initialize = internalMutation({
  args: {},
  handler: async (ctx) => {
    for (const key of ["teacher_prompts", "teacher_prompt_push"] as const)
      if (
        !(await ctx.db
          .query("feature_flags")
          .withIndex("key", (q) => q.eq("key", key))
          .unique())
      )
        await ctx.db.insert("feature_flags", { key, enabled: false });
    if (
      !(await ctx.db
        .query("prompt_policy")
        .withIndex("key", (q) => q.eq("key", "default"))
        .unique())
    )
      await ctx.db.insert("prompt_policy", { key: "default", ...defaults });
    if (
      !(await ctx.db
        .query("runtime_settings")
        .withIndex("key", (q) => q.eq("key", "default"))
        .unique())
    )
      await ctx.db.insert("runtime_settings", {
        key: "default",
        demoEnabled: false,
      });
  },
});
export const setFlag = internalMutation({
  args: {
    key: v.union(
      v.literal("teacher_prompts"),
      v.literal("teacher_prompt_push"),
    ),
    enabled: v.boolean(),
  },
  handler: async (ctx, a) => {
    const old = await ctx.db
      .query("feature_flags")
      .withIndex("key", (q) => q.eq("key", a.key))
      .unique();
    if (old) await ctx.db.patch(old._id, { enabled: a.enabled });
    else await ctx.db.insert("feature_flags", a);
  },
});
export const setDemoEnabled = internalMutation({
  args: { enabled: v.boolean() },
  handler: async (ctx, { enabled }) => {
    const s = await ctx.db
      .query("runtime_settings")
      .withIndex("key", (q) => q.eq("key", "default"))
      .unique();
    if (s) await ctx.db.patch(s._id, { demoEnabled: enabled });
    else
      await ctx.db.insert("runtime_settings", {
        key: "default",
        demoEnabled: enabled,
      });
  },
});
export const updatePolicy = internalMutation({
  args: {
    offsets: v.array(v.number()),
    grace: v.number(),
    maxSnoozes: v.number(),
  },
  handler: async (ctx, a) => {
    if (
      a.offsets.length !== 4 ||
      !a.offsets.every(
        (n, i) => Number.isInteger(n) && (i === 0 || n > a.offsets[i - 1]),
      ) ||
      a.offsets[0] < -30 ||
      a.offsets[3] > 180 ||
      !Number.isInteger(a.grace) ||
      a.grace < 1 ||
      a.grace > 60 ||
      !Number.isInteger(a.maxSnoozes) ||
      a.maxSnoozes < 0 ||
      a.maxSnoozes > 3
    )
      fail("TP_INVALID_INPUT");
    const prior = await ctx.db
      .query("prompt_policy")
      .withIndex("key", (q) => q.eq("key", "default"))
      .unique();
    if (
      prior &&
      prior.grace === a.grace &&
      prior.maxSnoozes === a.maxSnoozes &&
      prior.offsets.every((n, i) => n === a.offsets[i])
    )
      return;
    if (prior) await ctx.db.patch(prior._id, a);
    else await ctx.db.insert("prompt_policy", { key: "default", ...a });
    const open = await ctx.db
      .query("lessons")
      .withIndex("open", (q) =>
        q.eq("cancelled", undefined).eq("submitted", undefined),
      )
      .collect();
    for (const l of open) {
      await ctx.db.patch(l._id, { planRevision: l.planRevision + 1 });
      await planLesson(ctx, l._id);
    }
  },
});
