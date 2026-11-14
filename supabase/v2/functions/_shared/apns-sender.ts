import type { Delivery, PromptSender, SendResult } from "./prompt-dispatch.ts";
import { buildPromptPayload, UUID_PATTERN } from "./prompt-payload.ts";

export type ApnsFetch = (url: string, init: RequestInit) => Promise<Response>;
export type ApnsConfig = { keyId: string; teamId: string; privateKeyPem: string; topic: string };
export type ApnsRequest = { url: string; init: RequestInit; outboxId: string };
const hosts = { sandbox: "https://api.sandbox.push.apple.com", production: "https://api.push.apple.com" };
const encoder = new TextEncoder();
const failure = (error_code: string, retryable = false, invalidate_device = false): SendResult =>
  ({ accepted: false, error_code, retryable, invalidate_device });

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const encodedJson = (value: unknown) => base64url(encoder.encode(JSON.stringify(value)));

/** Cached per key/configuration, including concurrent callers; refresh at 45 minutes. */
export class ApnsProviderToken {
  private cached?: { token: string; issuedAt: number };
  private pending?: Promise<string>;
  private key?: Promise<CryptoKey>;
  constructor(private config: Pick<ApnsConfig, "keyId" | "teamId" | "privateKeyPem">,
    private now: () => number = Date.now) {}

  async get(): Promise<string> {
    const seconds = Math.floor(this.now() / 1000);
    if (this.cached && seconds >= this.cached.issuedAt && seconds - this.cached.issuedAt < 45 * 60) {
      return this.cached.token;
    }
    if (this.pending) return this.pending;
    this.pending = this.sign(seconds);
    try { return await this.pending; }
    finally { this.pending = undefined; }
  }

  private async sign(issuedAt: number): Promise<string> {
    try {
      if (!/^[A-Za-z0-9]{1,32}$/.test(this.config.keyId) || !/^[A-Za-z0-9]{1,32}$/.test(this.config.teamId)) {
        throw new Error("TP_INVALID_KEY_CONFIG");
      }
      if (!this.key) {
        const pem = this.config.privateKeyPem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s/g, "");
        const bytes = Uint8Array.from(atob(pem), (char) => char.charCodeAt(0));
        this.key = crypto.subtle.importKey("pkcs8", bytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
      }
      const input = `${encodedJson({ alg: "ES256", kid: this.config.keyId })}.${encodedJson({ iss: this.config.teamId, iat: issuedAt })}`;
      const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, await this.key, encoder.encode(input));
      const token = `${input}.${base64url(new Uint8Array(signature))}`;
      this.cached = { token, issuedAt };
      return token;
    } catch {
      this.key = undefined;
      throw new Error("TP_PROVIDER_AUTH_ERROR");
    }
  }
}

/** Reconstruct an allowlisted payload; never serialize the delivery object. */
export function buildApnsRequest(delivery: Delivery, topic: string, jwt: string, nowMs: number): ApnsRequest {
  const host = hosts[delivery.environment];
  const expires = Date.parse(delivery.expires_at);
  if (delivery.mode !== "apns" || !host || !UUID_PATTERN.test(delivery.outbox_id) ||
    !/^(?:[0-9a-f]{2}){16,256}$/.test(delivery.token) ||
    !/^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$/.test(topic) ||
    delivery.collapse_id !== `tp:${delivery.lesson_id}` ||
    delivery.thread_id !== `teacher-lesson:${delivery.lesson_id}` ||
    !Number.isFinite(expires) || expires <= nowMs || !Number.isFinite(nowMs)) {
    throw new Error("TP_INVALID_DELIVERY");
  }
  const body = JSON.stringify(buildPromptPayload(delivery.lesson_id, delivery.kind));
  if (encoder.encode(body).byteLength >= 4096) throw new Error("TP_INVALID_DELIVERY");
  return {
    url: `${host}/3/device/${delivery.token}`,
    outboxId: delivery.outbox_id,
    init: {
      method: "POST", redirect: "error",
      headers: {
        authorization: `bearer ${jwt}`, "content-type": "application/json",
        "apns-topic": topic, "apns-push-type": "alert", "apns-priority": "10",
        "apns-id": delivery.outbox_id, "apns-collapse-id": delivery.collapse_id,
        "apns-expiration": String(Math.floor(Math.min(expires, nowMs + 3_600_000) / 1000)),
      },
      body,
    },
  };
}

export function classifyApnsResponse(status: number, reason: unknown, providerId: string | null, outboxId: string): SendResult {
  if (status === 200) return {
    accepted: true, transport: "apns",
    provider_id: providerId && UUID_PATTERN.test(providerId.toLowerCase()) ? providerId.toLowerCase() : outboxId,
  };
  if (status === 410) return failure("unregistered", false, true);
  if (status === 400 && reason === "BadDeviceToken") return failure("bad_device_token", false, true);
  if (status === 403) return failure("forbidden");
  if (status === 429) return failure("rate_limited", true);
  if (status >= 500 && status <= 599) return failure("server_error", true);
  return failure("bad_request");
}

async function boundedReason(response: Response, signal: AbortSignal): Promise<unknown> {
  const reader = response.body?.getReader();
  if (!reader) return undefined;
  let size = 0;
  const chunks: Uint8Array[] = [];
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener("abort", cancel, { once: true });
  try {
    if (signal.aborted) { await reader.cancel(); return undefined; }
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1024) { await reader.cancel(); return undefined; }
      chunks.push(value);
    }
    const data = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
    return JSON.parse(new TextDecoder().decode(data))?.reason;
  } catch { return undefined; }
  finally { signal.removeEventListener("abort", cancel); reader.releaseLock(); }
}

/** Test this helper with an injected fake fetch; no global fetch fallback exists. */
export async function executeApnsRequest(request: ApnsRequest, fetchHttp2: ApnsFetch, timeoutMs = 10_000): Promise<SendResult> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<SendResult>((resolve) => {
    timer = setTimeout(() => { controller.abort(); resolve(failure("timeout", true)); }, Math.min(10_000, Math.max(1, timeoutMs)));
  });
  const execute = async (): Promise<SendResult> => {
    try {
      const response = await fetchHttp2(request.url, { ...request.init, signal: controller.signal });
      const reason = await boundedReason(response, controller.signal);
      return classifyApnsResponse(response.status, reason, response.headers.get("apns-id"), request.outboxId);
    } catch { return failure(controller.signal.aborted ? "timeout" : "transport_error", true); }
  };
  try { return await Promise.race([execute(), timeout]); }
  finally { clearTimeout(timer); }
}

export class ApnsSender implements PromptSender {
  private providerToken: ApnsProviderToken;
  constructor(private config: ApnsConfig, private fetchHttp2: ApnsFetch, private now: () => number = Date.now) {
    this.providerToken = new ApnsProviderToken(config, now);
  }
  async send(delivery: Delivery): Promise<SendResult> {
    if (delivery.mode !== "apns") return failure("mode_mismatch");
    let jwt: string;
    try { jwt = await this.providerToken.get(); }
    catch { return failure("provider_error"); }
    let request: ApnsRequest;
    try { request = buildApnsRequest(delivery, this.config.topic, jwt, this.now()); }
    catch { return failure("invalid_delivery"); }
    return executeApnsRequest(request, this.fetchHttp2);
  }
}
