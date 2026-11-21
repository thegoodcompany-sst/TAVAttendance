import { afterEach, expect, it, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { fixture } from "../tests/fixture";
afterEach(() => vi.useRealTimers());
it("denies takeover of either a token or a foreign installation across environments", async () => {
  const { lead, other } = await fixture(),
    id = crypto.randomUUID();
  const a = {
    p_installation_id: id,
    p_environment: "sandbox" as const,
    p_token: "ab".repeat(32),
  };
  const first = await lead.client.mutation(api.devices.register_device, a);
  expect(
    (await lead.client.mutation(api.devices.register_device, a)).device_id,
  ).toEqual(first.device_id);
  await lead.client.mutation(api.devices.unregister_device, {
    p_installation_id: id,
  });
  await expect(
    other.client.mutation(api.devices.register_device, {
      ...a,
      p_installation_id: crypto.randomUUID(),
    }),
  ).rejects.toThrow("TP_NOT_AVAILABLE");
  await expect(
    other.client.mutation(api.devices.register_device, {
      ...a,
      p_environment: "production",
      p_token: "cd".repeat(32),
    }),
  ).rejects.toThrow("TP_NOT_AVAILABLE");
});
it("revokes both environments after flag and profile deactivation, idempotently, owner only", async () => {
  const { t, lead, other } = await fixture(),
    id = crypto.randomUUID();
  for (const env of ["sandbox", "production"] as const)
    await lead.client.mutation(api.devices.register_device, {
      p_installation_id: id,
      p_token: "aa".repeat(32),
      p_environment: env,
    });
  expect(
    await other.client.mutation(api.devices.unregister_device, {
      p_installation_id: id,
    }),
  ).toEqual({ revoked: true });
  expect(
    (await t.run((ctx) => ctx.db.query("teacher_devices").collect())).every(
      (d) => d.revoked === undefined,
    ),
  ).toBe(true);
  await t.mutation(internal.settings.setFlag, {
    key: "teacher_prompts",
    enabled: false,
  });
  await t.run((ctx) => ctx.db.patch(lead.id, { active: false }));
  await lead.client.mutation(api.devices.unregister_device, {
    p_installation_id: id,
  });
  const after = await t.run((ctx) => ctx.db.query("teacher_devices").collect());
  expect(after.every((d) => d.revoked !== undefined)).toBe(true);
  await lead.client.mutation(api.devices.unregister_device, {
    p_installation_id: id,
  });
  expect(
    await t.run((ctx) => ctx.db.query("teacher_devices").collect()),
  ).toEqual(after);
});
it("keeps only the newest five devices", async () => {
  const { t, register } = await fixture();
  for (let i = 1; i <= 6; i++) await register(i);
  const ds = await t.run((ctx) => ctx.db.query("teacher_devices").collect());
  expect(ds.filter((d) => d.revoked === undefined)).toHaveLength(5);
  expect(ds[0].revoked).toBeDefined();
});
it.each(["x".repeat(64), "a".repeat(33), "ab", "ab".repeat(257)])(
  "rejects malformed device tokens",
  async (token) => {
    const { lead } = await fixture();
    await expect(
      lead.client.mutation(api.devices.register_device, {
        p_installation_id: crypto.randomUUID(),
        p_token: token,
        p_environment: "sandbox",
      }),
    ).rejects.toThrow("TP_INVALID_INPUT");
  },
);
