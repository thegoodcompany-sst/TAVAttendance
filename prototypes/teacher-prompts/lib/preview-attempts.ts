import { createHash } from "node:crypto";
import { isIP } from "node:net";

const WINDOW = 60_000;
const MAX_BACKOFF = 15 * WINDOW;
type Bucket = {
  count: number;
  until: number;
  strikes: number;
  touched: number;
};

/** Synchronous admission prevents concurrent requests from overspending a bucket.
 * Process-local: multiple replicas also require a shared perimeter rate limit.
 */
export function createPreviewLimiter() {
  const ips = new Map<string, Bucket>();
  const global: Bucket = { count: 0, until: 0, strikes: 0, touched: 0 };
  function consume(bucket: Bucket, limit: number, now: number) {
    if (now - bucket.touched >= MAX_BACKOFF * 2) bucket.strikes = 0;
    bucket.touched = now;
    if (now >= bucket.until) {
      bucket.count = 0;
      bucket.until = now + WINDOW;
    }
    if (bucket.count >= limit)
      return Math.max(1, Math.ceil((bucket.until - now) / 1000));
    bucket.count++;
    if (bucket.count === limit) {
      bucket.until = now + Math.min(MAX_BACKOFF, WINDOW * 2 ** bucket.strikes);
      bucket.strikes = Math.min(bucket.strikes + 1, 4);
    }
    return 0;
  }
  return {
    take(ip: string, now = Date.now()): number {
      // Global attempts include blocked per-IP guesses; rotating addresses cannot bypass it.
      const globalRetry = consume(global, 30, now);
      if (globalRetry) return globalRetry;
      for (const [key, bucket] of ips)
        if (now - bucket.touched >= MAX_BACKOFF * 2) ips.delete(key);
      // Hash addresses in ephemeral memory; never store codes or log addresses.
      const key = createHash("sha256").update(ip).digest("hex");
      let bucket = ips.get(key);
      if (!bucket) {
        if (ips.size >= 1024) return Math.ceil(MAX_BACKOFF / 1000);
        bucket = { count: 0, until: 0, strikes: 0, touched: now };
        ips.set(key, bucket);
      }
      return consume(bucket, 5, now);
    },
  };
}

/** Trust only an explicitly configured proxy that overwrites this header. */
export function previewClientIp(
  headers: Pick<Headers, "get">,
  trustProxy: boolean,
) {
  const raw = trustProxy ? headers.get("x-forwarded-for")?.trim() : undefined;
  if (!raw || !isIP(raw)) return "unknown";
  // Canonicalize IPv6 to prevent equivalent textual addresses creating new buckets.
  return isIP(raw) === 6 ? new URL(`http://[${raw}]/`).hostname : raw;
}
const state = globalThis as unknown as {
  tpPreviewAttempts?: ReturnType<typeof createPreviewLimiter>;
};
export const previewAttempts = (state.tpPreviewAttempts ??=
  createPreviewLimiter());
