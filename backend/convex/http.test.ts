import { afterEach, expect, it, vi } from "vitest";
import { fixture } from "../tests/fixture";

afterEach(() => vi.useRealTimers());
it("returns the same domain projection through authenticated JSON HTTP", async () => {
  const { lead, base, detail, other, t } = await fixture();
  const request = {
    method: "POST",
    body: JSON.stringify(base),
    headers: { "Content-Type": "application/json" },
  };
  const res = await lead.client.fetch("/v2/lesson_for_prompt", request);
  expect(res.status).toBe(200);
  expect((await res.json()).roster).toEqual((await detail()).roster);
  const denied = await other.client.fetch("/v2/lesson_for_prompt", request);
  expect(denied.status).toBe(404);
  expect(await denied.json()).toEqual({ error: "TP_NOT_AVAILABLE" });
  expect((await t.fetch("/v2/lesson_for_prompt", request)).status).toBe(401);
});
it.each(["{", "null", "[]"])(
  "maps malformed JSON objects to a stable client error",
  async (body) => {
    const { lead } = await fixture();
    const res = await lead.client.fetch("/v2/mark_all_present", {
      method: "POST",
      body,
    });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "TP_INVALID_INPUT" });
  },
);
