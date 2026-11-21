import { ConvexError } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";
import { getAuthUserId } from "@convex-dev/auth/server";

export const minute = 60_000,
  day = 1440 * minute;
export const iso = (ms: number) => new Date(ms).toISOString();
export const dateSG = (ms: number) => iso(ms + 8 * 60 * minute).slice(0, 10);
export const midnight = (date: string) => {
  const ms = Date.parse(date + "T00:00:00+08:00");
  if (!Number.isFinite(ms) || dateSG(ms) !== date) fail("TP_INVALID_INPUT");
  return ms;
};
export function fail(code: string): never {
  throw new ConvexError(code);
}
export const uuid = (s: string) => {
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(s))
    fail("TP_INVALID_INPUT");
  return s.toLowerCase();
};
export const emailKey = (s: string) => {
  const email = s.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254)
    fail("TP_INVALID_INPUT");
  return email;
};
export async function digest(s: string) {
  const bytes = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)),
  );
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
export const flag = async (ctx: QueryCtx, key: Doc<"feature_flags">["key"]) =>
  (
    await ctx.db
      .query("feature_flags")
      .withIndex("key", (q) => q.eq("key", key))
      .unique()
  )?.enabled === true;
export async function profile(ctx: QueryCtx) {
  const user = await getAuthUserId(ctx);
  if (!user) fail("sessionExpired");
  return (
    (await ctx.db
      .query("profiles")
      .withIndex("user", (q) => q.eq("user", user))
      .unique()) ?? fail("TP_NOT_AVAILABLE")
  );
}
export async function actor(ctx: QueryCtx) {
  const p = await profile(ctx);
  if (!p.active) fail("TP_NOT_AVAILABLE");
  if (!(await flag(ctx, "teacher_prompts"))) fail("TP_DISABLED");
  return p;
}
export async function review(ctx: QueryCtx, id: string) {
  const p = await actor(ctx);
  const l = await ctx.db
    .query("lessons")
    .withIndex("uuid", (q) => q.eq("uuid", uuid(id)))
    .unique();
  if (
    !l ||
    (p.role !== "admin" && l.lead !== p._id) ||
    (await ctx.db.get(l.class))?.studySpace !== false
  )
    fail("TP_NOT_AVAILABLE");
  return { p, l };
}
export function editError(l: Doc<"lessons">, admin: boolean, now = Date.now()) {
  if (l.cancelled !== undefined || l.submitted !== undefined)
    return "TP_LOCKED";
  if (now < l.start) return "TP_TOO_EARLY";
  if (!admin && midnight(dateSG(now)) - midnight(dateSG(l.start)) > 7 * day)
    return "TP_TOO_OLD";
  return null;
}
