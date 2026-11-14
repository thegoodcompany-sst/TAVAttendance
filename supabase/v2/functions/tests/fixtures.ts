import type { Claim, Delivery, PromptDb, SendResult } from "../_shared/prompt-dispatch.ts";

export const NOW = "2027-01-07T13:05:00.000Z";
export const uuid = (n: number) => `90000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
export function claimFixture(n = 1): Claim {
  return { outbox_id: uuid(n), plan_id: uuid(100), lesson_id: uuid(200), kind: "attendance",
    recipient_id: uuid(300), device_id: uuid(400 + n), plan_revision: "9007199254740993",
    lease_token: uuid(500 + n), lease_until: "2027-01-07T13:07:00.000Z", attempt_no: 1 };
}
export function deliveryFixture(claim = claimFixture()): Delivery {
  return { outbox_id: claim.outbox_id, lesson_id: claim.lesson_id, kind: claim.kind,
    token: "ab".repeat(32), environment: "sandbox", collapse_id: `tp:${claim.lesson_id}`,
    thread_id: `teacher-lesson:${claim.lesson_id}`, expires_at: "2027-01-07T13:15:00.000Z", mode: "dry_run" };
}
type Failure = Extract<SendResult, { accepted: false }>;
type Accepted = Extract<SendResult, { accepted: true }>;
type Row = { claim: Claim; delivery: Delivery; status: "pending" | "claimed" | "sent" | "failed" | "cancelled";
  available: number; deviceVersion: number; preparedVersion?: number };

/** Contract-shaped orchestration double, not a replacement for SQL scheduler tests. */
export class MemoryPromptDb implements PromptDb {
  rows: Row[];
  submitted = false;
  enabled = true;
  revoked = new Set<string>();
  calls: { operation: string; now: string }[] = [];
  receipts: { outbox_id: string; attempt: number; result: SendResult }[] = [];
  constructor(count = 1) {
    this.rows = Array.from({ length: count }, (_, i) => {
      const claim = claimFixture(i + 1);
      return { claim, delivery: deliveryFixture(claim), status: "pending", available: Date.parse(NOW), deviceVersion: 1 };
    });
  }
  async claim(now: string, limit: number): Promise<Claim[]> {
    this.calls.push({ operation: "claim", now });
    if (!this.enabled || this.submitted) return [];
    const rows = this.rows.filter((row) => row.status === "pending" && row.available <= Date.parse(now)).slice(0, limit);
    return rows.map((row) => {
      row.status = "claimed";
      row.claim = { ...row.claim, lease_token: uuid(600 + row.claim.attempt_no * 100 + this.rows.indexOf(row)),
        lease_until: new Date(Date.parse(now) + 120_000).toISOString() };
      return { ...row.claim };
    });
  }
  async prepare(claim: Claim, now: string): Promise<Delivery | null> {
    this.calls.push({ operation: "prepare", now });
    const row = this.rows.find((row) => row.claim.outbox_id === claim.outbox_id)!;
    if (!this.validLease(row, claim, now)) return null;
    if (this.submitted || !this.enabled) { row.status = "cancelled"; return null; }
    const hour = (new Date(now).getUTCHours() + 8) % 24;
    if (hour >= 22 || hour < 7) { row.status = "pending"; row.available = Date.parse(now) + 12 * 3_600_000; return null; }
    row.preparedVersion = row.deviceVersion;
    return { ...row.delivery };
  }
  private validLease(row: Row, claim: Claim, now: string): boolean {
    return row.status === "claimed" && row.claim.lease_token === claim.lease_token && Date.parse(claim.lease_until) > Date.parse(now);
  }
  async sent(claim: Claim, result: Accepted, now: string): Promise<boolean> {
    this.calls.push({ operation: "sent", now });
    const row = this.rows.find((row) => row.claim.outbox_id === claim.outbox_id)!;
    if (!this.validLease(row, claim, now)) return false;
    row.status = "sent";
    this.receipts.push({ outbox_id: claim.outbox_id, attempt: claim.attempt_no, result });
    return true;
  }
  async failed(claim: Claim, result: Failure, now: string): Promise<boolean> {
    this.calls.push({ operation: "failed", now });
    const row = this.rows.find((row) => row.claim.outbox_id === claim.outbox_id)!;
    if (!this.validLease(row, claim, now)) return false;
    this.receipts.push({ outbox_id: claim.outbox_id, attempt: claim.attempt_no, result });
    if (result.invalidate_device && row.deviceVersion === row.preparedVersion) this.revoked.add(claim.device_id!);
    if (result.retryable && claim.attempt_no < 3) {
      row.status = "pending";
      row.available = Date.parse(now) + (claim.attempt_no === 1 ? 60_000 : 300_000);
      row.claim.attempt_no++;
    } else row.status = "failed";
    return true;
  }
}
