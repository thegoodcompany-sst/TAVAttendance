import { expect, it } from "vitest";
import { sessionIdentity } from "@convex-dev/auth/test";
import { api, internal } from "./_generated/api";
import { digest } from "./lib/common";
import { authTest, credentials } from "../tests/fixture";

const email = "fixture@example.invalid";
it.each(["missing", "wrong", "inactive", "expired"] as const)(
  "denies password activation with %s provisioning",
  async (reason) => {
    const t = authTest(),
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
      t.mutation(api.auth.activate, {
        ...credentials(email),
        invitation: reason === "wrong" ? "" : invitation,
      }),
    ).rejects.toThrow("TP_NOT_AVAILABLE");
    expect(await t.run((ctx) => ctx.db.query("users").collect())).toHaveLength(
      0,
    );
  },
);

it("consumes the invitation once, rotates tokens and revokes the signed-out session", async () => {
  const t = authTest(),
    invitation = crypto.randomUUID(),
    { password } = credentials(email);
  const uuid = await t.mutation(internal.staff.provision, {
    name: "Test",
    role: "teacher",
    email,
    invitationHash: await digest(invitation),
  });
  const args = { email, password, invitation };
  expect(
    (await t.mutation(api.auth.activate, { ...args, password: "x" })).status,
  ).toBe("error");
  const activated = await t.mutation(api.auth.activate, args);
  if (activated.status !== "complete") throw new Error("Activation failed");
  await expect(t.mutation(api.auth.activate, args)).rejects.toThrow(
    "TP_NOT_AVAILABLE",
  );
  expect(
    (await t.mutation(api.auth.signIn, credentials(email, invitation))).status,
  ).toBe("error");
  const signedIn = await t.mutation(api.auth.signIn, {
    email: email.toUpperCase(),
    password,
  });
  if (signedIn.status !== "complete") throw new Error("Sign-in failed");
  const rotated = await t.mutation(api.auth.refreshSession, {
    refreshToken: signedIn.tokens.refreshToken,
  });
  if (rotated.kind !== "rotated") throw new Error("Refresh failed");
  expect(rotated.tokens.refreshToken === signedIn.tokens.refreshToken).toBe(
    false,
  );
  const client = t.withIdentity(sessionIdentity(rotated.tokens));
  expect((await client.query(api.teacher.my_profile)).id).toBe(uuid);
  await t.mutation(api.auth.signOut, {
    refreshToken: rotated.tokens.refreshToken,
  });
  expect(await client.query(api.auth.isAuthenticated)).toBe(false);
  expect(
    (await client.fetch("/v2/my_profile", { method: "POST", body: "{}" }))
      .status,
  ).toBe(401);
  await expect(client.query(api.teacher.my_profile)).rejects.toThrow(
    "sessionExpired",
  );
  expect(
    (
      await t.mutation(api.auth.refreshSession, {
        refreshToken: rotated.tokens.refreshToken,
      })
    ).kind,
  ).toBe("noSession");
  const active = t.withIdentity(sessionIdentity(activated.tokens));
  expect(await active.query(api.auth.isAuthenticated)).toBe(true);
  const profile = await t.run(
    async (ctx) => (await ctx.db.query("profiles").first())!._id,
  );
  await t.mutation(internal.staff.setAccess, {
    profile,
    active: false,
    role: "teacher",
  });
  expect((await t.mutation(api.auth.signIn, { email, password })).status).toBe(
    "error",
  );
  await expect(active.query(api.teacher.my_lessons_today, {})).rejects.toThrow(
    "TP_NOT_AVAILABLE",
  );
});

it("accepts the renewed invitation only once across competing activations", async () => {
  const t = authTest(),
    old = crypto.randomUUID(),
    invitation = crypto.randomUUID();
  const { password } = credentials(email);
  await t.mutation(internal.staff.provision, {
    name: "Test",
    role: "teacher",
    email,
    invitationHash: await digest(old),
  });
  await t.mutation(internal.staff.renewInvitation, {
    email,
    invitationHash: await digest(invitation),
  });
  await expect(
    t.mutation(api.auth.activate, { email, password, invitation: old }),
  ).rejects.toThrow("TP_NOT_AVAILABLE");
  const attempts = await Promise.allSettled(
    [password, crypto.randomUUID()].map((password) =>
      t.mutation(api.auth.activate, { email, password, invitation }),
    ),
  );
  expect(
    attempts.filter(
      (a) => a.status === "fulfilled" && a.value.status === "complete",
    ),
  ).toHaveLength(1);
  expect(await t.run((ctx) => ctx.db.query("users").collect())).toHaveLength(1);
  await expect(
    t.mutation(internal.staff.renewInvitation, {
      email,
      invitationHash: await digest(old),
    }),
  ).rejects.toThrow("TP_NOT_AVAILABLE");
});

it("commits the password component's verification rate limit across rejected sign-ins", async () => {
  const t = authTest(),
    invitation = crypto.randomUUID(),
    { password } = credentials(email);
  await t.mutation(internal.staff.provision, {
    name: "Test",
    role: "teacher",
    email,
    invitationHash: await digest(invitation),
  });
  expect(
    (await t.mutation(api.auth.activate, { email, password, invitation }))
      .status,
  ).toBe("complete");
  for (let i = 0; i < 5; i++) {
    expect(
      (await t.mutation(api.auth.signIn, credentials(email, invitation)))
        .status,
    ).toBe("error");
  }
  expect((await t.mutation(api.auth.signIn, { email, password })).status).toBe(
    "error",
  );
});
