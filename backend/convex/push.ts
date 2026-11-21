"use node";
import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { ApnsSender } from "./lib/push/apns_sender";
import { http2Fetch } from "./lib/push/apns_http2";
import { DryRunSender } from "./lib/push/dry_run_sender";
import type { Delivery, SendResult } from "./lib/push/prompt_dispatch";

const dry = new DryRunSender();
let apns: ApnsSender | undefined;
export async function dispatch(delivery: Delivery): Promise<SendResult> {
  if (delivery.mode === "dry_run") return dry.send(delivery);
  if (
    process.env.APNS_DRY_RUN !== "false" ||
    delivery.environment !== process.env.APNS_ENV
  )
    return {
      accepted: false,
      error_code: "mode_mismatch",
      retryable: false,
      invalidate_device: false,
    };
  if (!apns) {
    const raw = process.env.APNS_KEY_P8 ?? "";
    const key = raw.includes("BEGIN PRIVATE KEY")
      ? raw
      : Buffer.from(raw, "base64").toString("utf8");
    apns = new ApnsSender(
      {
        privateKeyPem: key,
        keyId: process.env.APNS_KEY_ID ?? "",
        teamId: process.env.APNS_TEAM_ID ?? "",
        topic: process.env.APNS_BUNDLE_ID ?? "com.tava.TAVAttendance",
      },
      http2Fetch,
    );
  }
  return apns.send(delivery);
}
export const send = internalAction({
  args: { id: v.id("outbox"), lease: v.string() },
  handler: async (ctx, args): Promise<void> => {
    const delivery = await ctx.runMutation(internal.queue.prepare, args);
    if (!delivery) return;
    const result = await dispatch(delivery);
    await ctx.runMutation(internal.queue.finish, { ...args, result });
  },
});
