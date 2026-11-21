import { beforeAll, describe, expect, test } from "bun:test";
import { ApnsProviderToken, buildApnsRequest, executeApnsRequest, type ApnsConfig, type ApnsFetch } from "../_shared/apns-sender.ts";
import { deliveryFixture, NOW, uuid } from "./fixtures.ts";

// Deliberately no ApnsSender or HTTP/2 transport import. All fetches below are fakes.
let config: ApnsConfig;
let publicKey: CryptoKey;
beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  publicKey = pair.publicKey;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  config = { keyId: "DEMO123456", teamId: "DEMO654321", topic: "org.example.tava",
    privateKeyPem: `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----` };
});
const unbase64 = (value: string) => Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
const delivery = () => ({ ...deliveryFixture(), mode: "apns" as const });
const request = () => buildApnsRequest(delivery(), config.topic, "fake.provider.token", Date.parse(NOW));

describe("APNs signing, request and response helpers (fake fetch only)", () => {
  test("WebCrypto ES256 JWT has correct header/claims and a verifiable 64-byte signature", async () => {
    const jwt = await new ApnsProviderToken(config, () => Date.parse(NOW)).get();
    const [header, claims, signature] = jwt.split(".");
    expect(JSON.parse(new TextDecoder().decode(unbase64(header)))).toEqual({ alg: "ES256", kid: config.keyId });
    expect(JSON.parse(new TextDecoder().decode(unbase64(claims)))).toEqual({ iss: config.teamId, iat: Date.parse(NOW) / 1000 });
    expect(unbase64(signature).length).toBe(64);
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey,
      unbase64(signature), new TextEncoder().encode(`${header}.${claims}`))).toBe(true);
  });
  test("provider token is cached across concurrent requests and refreshed before 50 minutes", async () => {
    let now = Date.parse(NOW);
    const provider = new ApnsProviderToken(config, () => now);
    const first = await Promise.all(Array.from({ length: 5 }, () => provider.get()));
    expect(new Set(first).size).toBe(1);
    now += 44 * 60_000;
    expect(await provider.get()).toBe(first[0]);
    now += 60_000;
    expect(await provider.get()).not.toBe(first[0]);
  });
  test("clock rollback replaces a future-issued cached JWT", async () => {
    let now = Date.parse(NOW);
    const provider = new ApnsProviderToken(config, () => now);
    const first = await provider.get();
    now -= 60_000;
    expect(await provider.get()).not.toBe(first);
  });
  test("invalid signing material yields a fixed error without the key", async () => {
    const provider = new ApnsProviderToken({ ...config, privateKeyPem: "do-not-log-key" });
    await expect(provider.get()).rejects.toThrow("TP_PROVIDER_AUTH_ERROR");
    await expect(provider.get()).rejects.toThrow("TP_PROVIDER_AUTH_ERROR");
  });
  for (const environment of ["sandbox", "production"] as const) {
    test(`${environment} exact host, POST, headers, payload, collapse and expiry`, () => {
      const item = { ...delivery(), environment };
      const built = buildApnsRequest(item, config.topic, "fake.provider.token", Date.parse(NOW));
      expect(built.url).toBe(`https://${environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"}/3/device/${item.token}`);
      expect(built.init.method).toBe("POST");
      expect(built.init.redirect).toBe("error");
      expect(built.init.headers).toEqual({ authorization: "bearer fake.provider.token", "content-type": "application/json",
        "apns-topic": config.topic, "apns-push-type": "alert", "apns-priority": "10", "apns-id": item.outbox_id,
        "apns-collapse-id": `tp:${item.lesson_id}`, "apns-expiration": String(Date.parse(item.expires_at) / 1000) });
      const body = JSON.parse(built.init.body as string);
      expect(body.aps["thread-id"]).toBe(item.thread_id);
      expect(body.aps.badge).toBeUndefined();
      expect(new TextEncoder().encode(item.collapse_id).byteLength).toBeLessThanOrEqual(64);
      expect(built.init.body).not.toContain(item.token);
    });
  }
  test("expiration cannot exceed now plus one hour", () => {
    const built = buildApnsRequest({ ...delivery(), expires_at: "2027-02-01T00:00:00Z" }, config.topic, "jwt", Date.parse(NOW));
    expect(new Headers(built.init.headers).get("apns-expiration")).toBe(String(Date.parse(NOW) / 1000 + 3600));
  });
  test("retry keeps stable APNs request and collapse identifiers", () => {
    const first = request(); const second = request();
    expect(new Headers(first.init.headers).get("apns-id")).toBe(new Headers(second.init.headers).get("apns-id"));
    expect(new Headers(first.init.headers).get("apns-collapse-id")).toBe(new Headers(second.init.headers).get("apns-collapse-id"));
  });
  test("rejects malformed/private transport fields and incompatible mode", () => {
    for (const change of [{ token: "not-a-token" }, { token: "a".repeat(33) }, { token: "a".repeat(514) },
      { environment: "https://example.invalid" }, { collapse_id: "Demo Student 01" }, { thread_id: "Demo Class" },
      { outbox_id: "bad-id" }, { expires_at: NOW }, { expires_at: "invalid" }, { mode: "dry_run" }]) {
      expect(() => buildApnsRequest({ ...delivery(), ...change } as ReturnType<typeof delivery>, config.topic, "jwt", Date.parse(NOW)))
        .toThrow("TP_INVALID_DELIVERY");
    }
  });
  const cases = [
    [200, undefined, undefined, false, false],
    [410, "Unregistered", "unregistered", false, true],
    [400, "BadDeviceToken", "bad_device_token", false, true],
    [400, "PayloadEmpty", "bad_request", false, false],
    [403, "ExpiredProviderToken", "forbidden", false, false],
    [404, "BadPath", "bad_request", false, false],
    [413, "PayloadTooLarge", "bad_request", false, false],
    [429, "TooManyRequests", "rate_limited", true, false],
    [500, "InternalServerError", "server_error", true, false],
    [503, "ServiceUnavailable", "server_error", true, false],
    [302, "redirect", "bad_request", false, false],
  ] as const;
  for (const [status, reason, code, retryable, invalidate] of cases) {
    test(`fake fetch status ${status} ${reason ?? "accepted"}`, async () => {
      let calls = 0;
      const fake: ApnsFetch = async (_url, init) => {
        calls++;
        expect(init.signal).toBeInstanceOf(AbortSignal);
        return new Response(reason ? JSON.stringify({ reason }) : null, { status, headers: { "apns-id": uuid(999) } });
      };
      const result = await executeApnsRequest(request(), fake);
      expect(calls).toBe(1);
      expect(result).toEqual(status === 200 ? { accepted: true, transport: "apns", provider_id: uuid(999) }
        : { accepted: false, error_code: code, retryable, invalidate_device: invalidate });
    });
  }
  test("untrusted provider ID is discarded", async () => {
    expect(await executeApnsRequest(request(), async () => new Response(null, { status: 200, headers: { "apns-id": "private-data" } })))
      .toEqual({ accepted: true, transport: "apns", provider_id: delivery().outbox_id });
  });
  test("provider body never leaks into error codes", async () => {
    expect(await executeApnsRequest(request(), async () => new Response('{"reason":"Demo Student 01 secret-token"}', { status: 400 })))
      .toEqual({ accepted: false, error_code: "bad_request", retryable: false, invalidate_device: false });
  });
  test("oversized and malformed error bodies are bounded and sanitized", async () => {
    for (const body of ["x".repeat(5000), "not json"]) {
      const result = await executeApnsRequest(request(), async () => new Response(body, { status: 400 }));
      expect(result).toEqual({ accepted: false, error_code: "bad_request", retryable: false, invalidate_device: false });
    }
  });
  test("network exception becomes retryable transport error", async () => {
    expect(await executeApnsRequest(request(), async () => { throw new Error("secret key body token"); }))
      .toEqual({ accepted: false, error_code: "transport_error", retryable: true, invalidate_device: false });
  });
  test("deadline aborts a stalled fake fetch even if it ignores cancellation", async () => {
    let signal: AbortSignal | null | undefined;
    const result = await executeApnsRequest(request(), async (_url, init) => {
      signal = init.signal; return await new Promise<Response>(() => {});
    }, 5);
    expect(result).toEqual({ accepted: false, error_code: "timeout", retryable: true, invalidate_device: false });
    expect(signal?.aborted).toBe(true);
  });
  test("deadline includes stalled response-body reading", async () => {
    const result = await executeApnsRequest(request(), async () => new Response(new ReadableStream({ start() {} }), { status: 400 }), 5);
    expect(result).toEqual({ accepted: false, error_code: "timeout", retryable: true, invalidate_device: false });
  });
});
