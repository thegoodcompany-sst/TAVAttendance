export type Claim = {
  outbox_id: string; plan_id: string; lesson_id: string;
  kind: "heads_up" | "attendance" | "follow_up" | "final";
  recipient_id: string; device_id: string | null; plan_revision: string;
  lease_token: string; lease_until: string; attempt_no: number;
};
export type Delivery = {
  outbox_id: string; lesson_id: string; kind: Claim["kind"];
  token: string; environment: "sandbox" | "production"; collapse_id: string;
  thread_id: string; expires_at: string; mode: "dry_run" | "apns";
};
export type SendResult =
  | { accepted: true; provider_id: string; transport: "dry_run" | "apns" }
  | { accepted: false; error_code: string; retryable: boolean; invalidate_device: boolean };
export interface PromptDb {
  claim(now: string, limit: number): Promise<Claim[]>;
  prepare(claim: Claim, now: string): Promise<Delivery | null>;
  sent(claim: Claim, result: Extract<SendResult, { accepted: true }>, now: string): Promise<boolean>;
  failed(claim: Claim, result: Extract<SendResult, { accepted: false }>, now: string): Promise<boolean>;
}
export interface PromptSender { send(delivery: Delivery): Promise<SendResult> }

export const ERROR_CODES = [
  "transport_error", "timeout", "rate_limited", "server_error",
  "bad_device_token", "unregistered", "forbidden", "bad_request",
  "invalid_delivery", "mode_mismatch", "provider_error",
] as const;
const allowedErrors = new Set<string>(ERROR_CODES);

export function transportFailure(): Extract<SendResult, { accepted: false }> {
  return { accepted: false, error_code: "transport_error", retryable: true, invalidate_device: false };
}

/** Only fixed codes cross into the audit store. A sender's exception/body never does. */
function sanitizedFailure(result: Extract<SendResult, { accepted: false }>) {
  if (!allowedErrors.has(result.error_code)) return transportFailure();
  return {
    accepted: false as const,
    error_code: result.error_code,
    retryable: result.retryable === true,
    invalidate_device: result.invalidate_device === true &&
      (result.error_code === "bad_device_token" || result.error_code === "unregistered"),
  };
}

export async function dispatchDuePrompts(args: {
  db: PromptDb; sender: PromptSender; now: () => string; limit?: number;
}): Promise<{ claimed: number; accepted: number; failed: number; suppressed: number }> {
  const { db, sender, now } = args;
  const limit = args.limit ?? 50;
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("TP_INVALID_LIMIT");
  let claims: Claim[];
  try { claims = await db.claim(now(), limit); }
  catch { throw new Error("TP_DATABASE_ERROR"); }
  const counts = { claimed: claims.length, accepted: 0, failed: 0, suppressed: 0 };
  let cursor = 0;
  let databaseFailed = false;
  const worker = async () => {
    while (!databaseFailed && cursor < claims.length) {
      const claim = claims[cursor++];
      try {
        // SQL rechecks submission, flags, quiet hours, version, ownership and lease.
        const delivery = await db.prepare(claim, now());
        if (!delivery) { counts.suppressed++; continue; }
        let result: SendResult;
        try { result = await sender.send(delivery); }
        catch { result = transportFailure(); }
        // A DB failure is not a transport failure: never overwrite an accepted attempt.
        const recorded = result.accepted
          ? await db.sent(claim, result, now())
          : await db.failed(claim, sanitizedFailure(result), now());
        if (!recorded) counts.suppressed++;
        else if (result.accepted) counts.accepted++;
        else counts.failed++;
      } catch {
        databaseFailed = true;
        throw new Error("TP_DATABASE_ERROR");
      }
    }
  };
  // Drain in-flight workers before returning an invocation failure.
  const workers = await Promise.allSettled(Array.from({ length: Math.min(5, claims.length) }, worker));
  if (workers.some((result) => result.status === "rejected")) throw new Error("TP_DATABASE_ERROR");
  return counts;
}
