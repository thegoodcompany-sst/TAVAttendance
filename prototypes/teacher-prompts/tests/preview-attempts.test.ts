import { expect, it } from "vitest";
import { createPreviewLimiter, previewClientIp } from "../lib/preview-attempts";
it("limits each IP independently and doubles backoff on repeated bursts", () => {
  const limiter = createPreviewLimiter();
  for (let i = 0; i < 5; i++) expect(limiter.take("192.0.2.1", 1000)).toBe(0);
  expect(limiter.take("192.0.2.1", 1000)).toBe(60);
  expect(limiter.take("192.0.2.2", 1000)).toBe(0);
  for (let i = 0; i < 5; i++) expect(limiter.take("192.0.2.1", 61000)).toBe(0);
  expect(limiter.take("192.0.2.1", 61000)).toBe(120);
  expect(limiter.take("192.0.2.1", 121000)).toBe(60);
  expect(limiter.take("192.0.2.1", 181000)).toBe(0);
});
it("globally bounds attempts even with 100 rotating addresses", () => {
  const limiter = createPreviewLimiter();
  const attempts = Array.from({ length: 100 }, (_, i) =>
    limiter.take(`192.0.2.${i}`, 1000),
  );
  expect(attempts.filter((x) => x === 0)).toHaveLength(30);
  expect(attempts.filter((x) => x > 0)).toHaveLength(70);
});
it("does not extend cooldown on blocked traffic and resets after inactivity", () => {
  const limiter = createPreviewLimiter();
  for (let i = 0; i < 5; i++) limiter.take("ip", 1000);
  expect(limiter.take("ip", 60000)).toBe(1);
  expect(limiter.take("ip", 61000)).toBe(0);
  for (let i = 0; i < 5; i++) expect(limiter.take("ip", 2000000)).toBe(0);
  expect(limiter.take("ip", 2000000)).toBe(60);
});
it("ignores untrusted headers, rejects lists, and normalizes IPv6", () => {
  const headers = new Headers({ "x-forwarded-for": "192.0.2.1" });
  expect(previewClientIp(headers, false)).toBe("unknown");
  expect(previewClientIp(headers, true)).toBe("192.0.2.1");
  headers.set("x-forwarded-for", "192.0.2.1, 192.0.2.2");
  expect(previewClientIp(headers, true)).toBe("unknown");
  headers.set("x-forwarded-for", "0:0:0:0:0:0:0:1");
  expect(previewClientIp(headers, true)).toBe("[::1]");
});
