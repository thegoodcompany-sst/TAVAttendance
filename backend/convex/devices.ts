import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { actor, profile, fail, iso, uuid } from "./lib/common";
import { environment } from "./schema";

export const register_device = mutation({
  args: {
    p_installation_id: v.string(),
    p_token: v.string(),
    p_environment: environment,
  },
  handler: async (ctx, a) => {
    const p = await actor(ctx),
      installation = uuid(a.p_installation_id),
      token = a.p_token;
    if (!/^(?:[0-9a-f]{2}){16,256}$/.test(token)) fail("TP_INVALID_INPUT");
    const env = a.p_environment;
    const byToken = await ctx.db
      .query("teacher_devices")
      .withIndex("token", (q) => q.eq("environment", env).eq("token", token))
      .unique();
    const byInstall = await ctx.db
      .query("teacher_devices")
      .withIndex("installation", (q) =>
        q
          .eq("owner", p._id)
          .eq("installation", installation)
          .eq("environment", env),
      )
      .unique();
    const acrossEnvironments = await ctx.db
      .query("teacher_devices")
      .withIndex("installation_owner", (q) =>
        q.eq("installation", installation),
      )
      .collect();
    if (
      (byToken && byToken.owner !== p._id) ||
      acrossEnvironments.some((d) => d.owner !== p._id)
    )
      fail("TP_NOT_AVAILABLE");
    if (byToken && byInstall && byInstall._id !== byToken._id)
      fail("TP_INVALID_INPUT");
    const old = byInstall ?? byToken,
      seen = Math.max(Date.now(), (old?.seen ?? 0) + 1),
      device_id = old?.uuid ?? crypto.randomUUID();
    const fields = { seen, installation, token, revoked: undefined };
    if (old) await ctx.db.patch(old._id, fields);
    else
      await ctx.db.insert("teacher_devices", {
        ...fields,
        owner: p._id,
        uuid: device_id,
        environment: env,
        demo: p.demo,
      });
    const active = await ctx.db
      .query("teacher_devices")
      .withIndex("active", (q) => q.eq("owner", p._id).eq("revoked", undefined))
      .collect();
    for (const d of active.slice(0, -5))
      await ctx.db.patch(d._id, { revoked: Date.now() });
    return { device_id, last_seen_at: iso(seen), environment: env };
  },
});
export const unregister_device = mutation({
  args: { p_installation_id: v.string() },
  handler: async (ctx, a) => {
    const p = await profile(ctx),
      id = uuid(a.p_installation_id);
    const rows = await ctx.db
      .query("teacher_devices")
      .withIndex("installation", (q) =>
        q.eq("owner", p._id).eq("installation", id),
      )
      .collect();
    for (const d of rows)
      if (d.revoked === undefined)
        await ctx.db.patch(d._id, { revoked: Date.now() });
    return { revoked: true };
  },
});
