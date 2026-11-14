import type { Delivery, PromptSender, SendResult } from "./prompt-dispatch.ts";
import { buildPromptPayload, UUID_PATTERN } from "./prompt-payload.ts";

/** No console, network, or separate log: db.sent owns the durable dry-run receipt. */
export class DryRunSender implements PromptSender {
  async send(delivery: Delivery): Promise<SendResult> {
    if (delivery.mode !== "dry_run") {
      return { accepted: false, error_code: "mode_mismatch", retryable: false, invalidate_device: false };
    }
    try {
      buildPromptPayload(delivery.lesson_id, delivery.kind);
      if (!UUID_PATTERN.test(delivery.outbox_id)) throw new Error("TP_INVALID_DELIVERY");
    } catch {
      return { accepted: false, error_code: "invalid_delivery", retryable: false, invalidate_device: false };
    }
    return { accepted: true, provider_id: delivery.outbox_id, transport: "dry_run" };
  }
}
