import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { convexTest } from "convex-test";
import schema from "./schema";
import { api, internal } from "./_generated/api";
import { digest } from "./lib/common";
import { modules } from "../tests/fixture";

beforeEach(() => {
  vi.stubEnv("AUTH_LOG_LEVEL", "ERROR");
});
afterEach(() => vi.unstubAllEnvs());
it.each(["missing", "wrong", "inactive", "expired"] as const)(
  "denies password activation with %s provisioning",
  async (reason) => {
    const t = convexTest(schema, modules),
      email = "fixture@example.invalid",
      invitation = crypto.randomUUID();
    if (reason !== "missing") {
      await t.mutation(internal.staff.provision, {
        name: "Test",
        role: "teacher",
        email,
        invitationHash: await digest(invitation),
      });
      await t.run(async (ctx) => {
        const p = (await ctx.db.query("profiles").first())!;
        if (reason === "inactive") await ctx.db.patch(p._id, { active: false });
        if (reason === "expired")
          await ctx.db.patch(p._id, { invitationExpires: Date.now() - 1000 });
      });
    }
    await expect(
      t.action(api.auth.signIn, {
        provider: "password",
        params: {
          flow: "signUp",
          email,
          password: "test-password",
          invitation: reason === "wrong" ? crypto.randomUUID() : invitation,
          role: "admin",
        },
      }),
    ).rejects.toThrow("TP_NOT_AVAILABLE");
    expect(
      await t.run((ctx) => ctx.db.query("authAccounts").collect()),
    ).toHaveLength(0);
    expect(await t.run((ctx) => ctx.db.query("users").collect())).toHaveLength(
      0,
    );
  },
);
