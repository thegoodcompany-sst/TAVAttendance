import type { Claim, Delivery } from "../convex/lib/push/prompt_dispatch";

export const NOW = "2027-01-07T13:05:00.000Z";
export const uuid = (n: number) =>
  `90000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
export function claimFixture(n = 1): Claim {
  return {
    outbox_id: uuid(n),
    plan_id: uuid(100),
    lesson_id: uuid(200),
    kind: "attendance",
    recipient_id: uuid(300),
    device_id: uuid(400 + n),
    plan_revision: "9007199254740993",
    lease_token: uuid(500 + n),
    lease_until: "2027-01-07T13:07:00.000Z",
    attempt_no: 1,
  };
}
export function deliveryFixture(claim = claimFixture()): Delivery {
  return {
    outbox_id: claim.outbox_id,
    lesson_id: claim.lesson_id,
    kind: claim.kind,
    token: "ab".repeat(32),
    environment: "sandbox",
    collapse_id: `tp:${claim.lesson_id}`,
    thread_id: `teacher-lesson:${claim.lesson_id}`,
    expires_at: "2027-01-07T13:15:00.000Z",
    mode: "dry_run",
  };
}
