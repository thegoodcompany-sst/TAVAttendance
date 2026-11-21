export type Claim = {
  outbox_id: string;
  plan_id: string;
  lesson_id: string;
  kind: "heads_up" | "attendance" | "follow_up" | "final";
  recipient_id: string;
  device_id: string | null;
  plan_revision: string;
  lease_token: string;
  lease_until: string;
  attempt_no: number;
};
export type Delivery = {
  outbox_id: string;
  lesson_id: string;
  kind: Claim["kind"];
  token: string;
  environment: "sandbox" | "production";
  collapse_id: string;
  thread_id: string;
  expires_at: string;
  mode: "dry_run" | "apns";
};
export type SendResult =
  | { accepted: true; provider_id: string; transport: "dry_run" | "apns" }
  | {
      accepted: false;
      error_code: string;
      retryable: boolean;
      invalidate_device: boolean;
    };
export interface PromptSender {
  send(delivery: Delivery): Promise<SendResult>;
}
