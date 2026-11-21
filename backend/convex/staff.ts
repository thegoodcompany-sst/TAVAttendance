import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { day, emailKey, fail } from "./lib/common";
import { role } from "./schema";

// The operator gives the matching random activation secret to its intended teacher privately.
export const provision = internalMutation({
  args: {
    email: v.string(),
    name: v.string(),
    role,
    invitationHash: v.string(),
  },
  handler: async (ctx, args) => {
    const email = emailKey(args.email),
      name = args.name.trim();
    if (
      !name ||
      name.length > 80 ||
      !/^[0-9a-f]{64}$/.test(args.invitationHash)
    )
      fail("TP_INVALID_INPUT");
    const existing = await ctx.db
      .query("profiles")
      .withIndex("email", (q) => q.eq("email", email))
      .unique();
    if (existing) fail("TP_CONFLICT");
    const uuid = crypto.randomUUID();
    await ctx.db.insert("profiles", {
      email,
      name,
      uuid,
      role: args.role,
      active: true,
      invitationHash: args.invitationHash,
      invitationExpires: Date.now() + day,
    });
    return uuid;
  },
});

// Reassignment must precede loss of the accountable role.
export const setAccess = internalMutation({
  args: { profile: v.id("profiles"), active: v.boolean(), role },
  handler: async (ctx, a) => {
    const p = await ctx.db.get(a.profile);
    if (!p) fail("TP_NOT_AVAILABLE");
    if (!a.active || a.role !== "teacher") {
      const rule = await ctx.db
        .query("timetable_rules")
        .withIndex("teacher", (q) => q.eq("teacher", p._id))
        .filter((q) => q.eq(q.field("active"), true))
        .first();
      const lesson = await ctx.db
        .query("lessons")
        .withIndex("lead_start", (q) => q.eq("lead", p._id))
        .filter((q) =>
          q.and(
            q.eq(q.field("cancelled"), undefined),
            q.eq(q.field("submitted"), undefined),
          ),
        )
        .first();
      if (rule || lesson) fail("TP_CONFLICT");
    }
    await ctx.db.patch(p._id, { active: a.active, role: a.role });
  },
});
export const renewInvitation = internalMutation({
  args: { email: v.string(), invitationHash: v.string() },
  handler: async (ctx, a) => {
    const email = emailKey(a.email);
    const p = await ctx.db
      .query("profiles")
      .withIndex("email", (q) => q.eq("email", email))
      .unique();
    if (!p?.active || p.user) fail("TP_NOT_AVAILABLE");
    if (!/^[0-9a-f]{64}$/.test(a.invitationHash)) fail("TP_INVALID_INPUT");
    await ctx.db.patch(p._id, {
      invitationHash: a.invitationHash,
      invitationExpires: Date.now() + day,
    });
  },
});

// Only the guarded password recipe invokes this callback. The activating
// mutation links the returned ID to its provisioned profile before committing.
export const createPasswordUser = internalMutation({
  args: {
    method: v.object({
      name: v.literal("usernamePassword"),
      profile: v.object({}),
    }),
  },
  returns: v.id("users"),
  handler: (ctx) => ctx.db.insert("users", {}),
});
