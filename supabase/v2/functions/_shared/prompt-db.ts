import type { Claim, Delivery, PromptDb, SendResult } from "./prompt-dispatch.ts";

export type WorkerRpc = "scheduler_tick" | "prepare_prompt_delivery" | "mark_prompt_sent" | "mark_prompt_failed";
export type RpcCall = (name: WorkerRpc, args: Record<string, unknown>) => Promise<unknown>;

/** Both adapters share exactly the same named worker RPC arguments. */
export class RpcPromptDb implements PromptDb {
  constructor(private rpc: RpcCall) {}
  async claim(now: string, limit: number): Promise<Claim[]> {
    const rows = await this.rpc("scheduler_tick", { p_now: now, p_limit: limit });
    if (!Array.isArray(rows)) throw new Error("TP_DATABASE_ERROR");
    return rows as Claim[];
  }
  async prepare(claim: Claim, now: string): Promise<Delivery | null> {
    return await this.rpc("prepare_prompt_delivery", {
      p_outbox_id: claim.outbox_id, p_lease_token: claim.lease_token, p_now: now,
    }) as Delivery | null;
  }
  async sent(claim: Claim, result: Extract<SendResult, { accepted: true }>, now: string): Promise<boolean> {
    return await this.rpc("mark_prompt_sent", {
      p_outbox_id: claim.outbox_id, p_lease_token: claim.lease_token,
      p_provider_id: result.provider_id, p_transport: result.transport, p_now: now,
    }) === true;
  }
  async failed(claim: Claim, result: Extract<SendResult, { accepted: false }>, now: string): Promise<boolean> {
    return await this.rpc("mark_prompt_failed", {
      p_outbox_id: claim.outbox_id, p_lease_token: claim.lease_token, p_error_code: result.error_code,
      p_retryable: result.retryable, p_invalidate_device: result.invalidate_device, p_now: now,
    }) === true;
  }
}
