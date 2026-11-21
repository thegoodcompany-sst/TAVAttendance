import { convexTest } from "convex-test";
import { registerCore, sessionIdentity } from "@convex-dev/auth/test";
import { registerPassword } from "@convex-dev/auth/components/password/test";
import { registerUsername } from "@convex-dev/auth/components/username/test";
import { digest } from "../convex/lib/common";
import { vi } from "vitest";
import schema from "../convex/schema";
import { api, internal } from "../convex/_generated/api";
export const now = Date.parse("2027-01-07T13:00:00Z");
export const modules = import.meta.glob([
  "../convex/**/*.{ts,js}",
  "!../convex/**/*.test.ts",
]);
export function credentials(
  email: string,
  password: string = crypto.randomUUID(),
) {
  return { email, password };
}

export function authTest() {
  const t = convexTest(schema, modules);
  registerCore(t);
  registerPassword(t);
  registerUsername(t);
  return t;
}
export async function fixture(minutes = 0) {
  vi.useFakeTimers();
  vi.setSystemTime(now);
  const t = authTest();
  await t.mutation(internal.settings.initialize, {});
  await t.mutation(internal.settings.setFlag, {
    key: "teacher_prompts",
    enabled: true,
  });
  await t.mutation(internal.settings.setDemoEnabled, { enabled: true });
  async function staff(name: string, role: "admin" | "teacher") {
    const email = name + "@example.invalid";
    const invitation = crypto.randomUUID();
    const uuid = await t.mutation(internal.staff.provision, {
      email,
      name,
      role,
      invitationHash: await digest(invitation),
    });
    const result = await t.mutation(api.auth.activate, {
      ...credentials(email),
      invitation,
    });
    if (result.status !== "complete")
      throw new Error("Fixture activation failed");
    const id = await t.run(
      async (ctx) =>
        (await ctx.db
          .query("profiles")
          .withIndex("uuid", (q) => q.eq("uuid", uuid))
          .unique())!._id,
    );
    return {
      uuid,
      id,
      email,
      client: t.withIdentity({
        ...sessionIdentity(result.tokens),
        role: "admin",
      }),
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
