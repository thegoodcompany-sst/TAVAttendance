import { convexTest } from "convex-test";
import { vi } from "vitest";
import schema from "../convex/schema";
import { api, internal } from "../convex/_generated/api";
export const now = Date.parse("2027-01-07T13:00:00Z");
export const modules = import.meta.glob([
  "../convex/**/*.{ts,js}",
  "!../convex/**/*.test.ts",
]);
export async function fixture(minutes = 0) {
  vi.useFakeTimers();
  vi.setSystemTime(now);
  const t = convexTest(schema, modules);
  await t.mutation(internal.settings.initialize, {});
  await t.mutation(internal.settings.setFlag, {
    key: "teacher_prompts",
    enabled: true,
  });
  await t.mutation(internal.settings.setDemoEnabled, { enabled: true });
  async function staff(name: string, role: "admin" | "teacher") {
    const email = name + "@example.invalid";
    const uuid = await t.mutation(internal.staff.provision, {
      email,
      name,
      role,
      invitationHash: "1".repeat(64),
    });
    const { id, user } = await t.run(async (ctx) => {
      const p = (await ctx.db
        .query("profiles")
        .withIndex("email", (q) => q.eq("email", email))
        .unique())!;
      const user = await ctx.db.insert("users", { email });
      await ctx.db.patch(p._id, { user });
      return { id: p._id, user };
    });
    return {
      uuid,
      id,
      email,
      client: t.withIdentity({ subject: user + "|test", role: "admin" }),
    };
  }
  const lead = await staff("lead", "teacher"),
    other = await staff("other", "teacher"),
    admin = await staff("admin", "admin");
  const { lesson_id, tag } = await t.mutation(internal.seed.demo, {
    email: lead.email,
    minutes,
  });
  const l = (await t.run((ctx) => ctx.db.query("lessons").first()))!;
  const base = { p_lesson_id: lesson_id };
  const detail = () => lead.client.query(api.teacher.lesson_for_prompt, base);
  const mutation = () => ({ ...base, p_mutation_id: crypto.randomUUID() });
  const register = (n = 1) =>
    lead.client.mutation(api.devices.register_device, {
      p_installation_id: crypto.randomUUID(),
      p_token: n.toString(16).padStart(64, "0"),
      p_environment: "sandbox",
    });
  return { t, lead, other, admin, l, tag, base, detail, mutation, register };
}
