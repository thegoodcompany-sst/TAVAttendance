import { describe, expect, test } from "bun:test";
import { dispatchDuePrompts, type PromptSender, type SendResult } from "../_shared/prompt-dispatch.ts";
import { DryRunSender } from "../_shared/dry-run-sender.ts";
import { MemoryPromptDb, NOW } from "./fixtures.ts";

const retry: SendResult = { accepted: false, error_code: "timeout", retryable: true, invalidate_device: false };
describe("dispatch orchestration", () => {
  test("claims once; repeat tick cannot resend accepted work; durable dry-run receipt", async () => {
    const db = new MemoryPromptDb(2);
    const args = { db, sender: new DryRunSender(), now: () => NOW };
    expect(await dispatchDuePrompts(args)).toEqual({ claimed: 2, accepted: 2, failed: 0, suppressed: 0 });
    expect(await dispatchDuePrompts(args)).toEqual({ claimed: 0, accepted: 0, failed: 0, suppressed: 0 });
    expect(db.receipts).toHaveLength(2);
    for (const receipt of db.receipts) expect(receipt.result).toEqual({ accepted: true, transport: "dry_run", provider_id: receipt.outbox_id });
    expect(JSON.stringify(db.receipts)).not.toContain("abab");
  });
  test("disabled flag and no claimable work perform no sends", async () => {
    const db = new MemoryPromptDb(); db.enabled = false;
    const result = await dispatchDuePrompts({ db, sender: { send: async () => { throw new Error("must not send"); } }, now: () => NOW });
    expect(result.claimed).toBe(0);
    expect(db.calls.map((call) => call.operation)).toEqual(["claim"]);
  });
  test("submission between claim and prepare suppresses all devices", async () => {
    const db = new MemoryPromptDb(3);
    const claim = db.claim.bind(db);
    db.claim = async (...args) => { const rows = await claim(...args); db.submitted = true; return rows; };
    let sends = 0;
    const result = await dispatchDuePrompts({ db, sender: { send: async () => { sends++; return retry; } }, now: () => NOW });
    expect(result).toEqual({ claimed: 3, accepted: 0, failed: 0, suppressed: 3 });
    expect(sends).toBe(0);
    expect(db.receipts).toEqual([]);
  });
  test("fresh clock at prepare suppresses a tick crossing into Singapore quiet hours", async () => {
    const db = new MemoryPromptDb();
    const times = ["2027-01-07T13:59:59.000Z", "2027-01-07T14:00:00.000Z"];
    const result = await dispatchDuePrompts({ db, sender: new DryRunSender(), now: () => times.shift()! });
    expect(result.suppressed).toBe(1);
    expect(db.receipts).toHaveLength(0);
    expect(db.calls.map((call) => call.now)).toEqual(["2027-01-07T13:59:59.000Z", "2027-01-07T14:00:00.000Z"]);
  });
  test("fresh completion clock and expired lease reject stale acknowledgement", async () => {
    const db = new MemoryPromptDb();
    const times = [NOW, NOW, "2027-01-07T13:08:00.000Z"];
    const result = await dispatchDuePrompts({ db, sender: new DryRunSender(), now: () => times.shift()! });
    expect(result).toEqual({ claimed: 1, accepted: 0, failed: 0, suppressed: 1 });
    expect(db.receipts).toHaveLength(0);
    expect(db.calls[2].now).toBe("2027-01-07T13:08:00.000Z");
  });
  test("partial device failure retries only failed device at one minute", async () => {
    const db = new MemoryPromptDb(2);
    let now = NOW;
    const dry = new DryRunSender();
    const sender: PromptSender = { send: (delivery) => delivery.outbox_id === db.rows[1].claim.outbox_id
      ? Promise.resolve(retry) : dry.send(delivery) };
    expect(await dispatchDuePrompts({ db, sender, now: () => now })).toEqual({ claimed: 2, accepted: 1, failed: 1, suppressed: 0 });
    expect((await dispatchDuePrompts({ db, sender, now: () => now })).claimed).toBe(0);
    now = "2027-01-07T13:06:00.000Z";
    expect((await dispatchDuePrompts({ db, sender: dry, now: () => now })).accepted).toBe(1);
    expect(db.receipts.map((receipt) => receipt.attempt)).toEqual([1, 1, 2]);
  });
  test("SQL double owns one/five minute retry pacing and three-attempt cap", async () => {
    const db = new MemoryPromptDb(); const sender: PromptSender = { send: async () => retry };
    for (const now of [NOW, "2027-01-07T13:06:00.000Z", "2027-01-07T13:11:00.000Z"]) {
      expect((await dispatchDuePrompts({ db, sender, now: () => now })).failed).toBe(1);
    }
    expect(db.rows[0].status).toBe("failed");
    expect((await dispatchDuePrompts({ db, sender, now: () => "2027-01-07T13:20:00.000Z" })).claimed).toBe(0);
    expect(db.receipts).toHaveLength(3);
  });
  test("device invalidation is recorded through failed RPC; fresh registration survives", async () => {
    for (const rotate of [false, true]) {
      const db = new MemoryPromptDb();
      const sender: PromptSender = { send: async () => {
        if (rotate) db.rows[0].deviceVersion++;
        return { accepted: false, error_code: "unregistered", retryable: false, invalidate_device: true };
      } };
      await dispatchDuePrompts({ db, sender, now: () => NOW });
      expect(db.revoked.size).toBe(rotate ? 0 : 1);
      expect(db.rows[0].status).toBe("failed");
    }
  });
  test("at most five deliveries run concurrently even with a full batch", async () => {
    const db = new MemoryPromptDb(50);
    let active = 0, peak = 0;
    const dry = new DryRunSender();
    const sender: PromptSender = { send: async (delivery) => {
      active++; peak = Math.max(peak, active);
      await Bun.sleep(2);
      active--;
      return dry.send(delivery);
    } };
    expect((await dispatchDuePrompts({ db, sender, now: () => NOW })).accepted).toBe(50);
    expect(peak).toBe(5);
  });
  test("sender exceptions and unknown error strings are sanitized retryable errors", async () => {
    for (const throws of [false, true]) {
      const db = new MemoryPromptDb();
      await dispatchDuePrompts({ db, now: () => NOW, sender: { send: async () => {
        if (throws) throw new Error("Demo Student 01 token=secret");
        return { accepted: false, error_code: "Demo Student 01 token=secret", retryable: false, invalidate_device: true };
      } } });
      expect(db.receipts[0].result).toEqual({ accepted: false, error_code: "transport_error", retryable: true, invalidate_device: false });
    }
  });
  test("403 cannot invalidate a token even with an incorrect sender flag", async () => {
    const db = new MemoryPromptDb();
    await dispatchDuePrompts({ db, now: () => NOW, sender: { send: async () =>
      ({ accepted: false, error_code: "forbidden", retryable: false, invalidate_device: true }) } });
    expect(db.revoked.size).toBe(0);
  });
  for (const operation of ["claim", "prepare", "sent", "failed"] as const) {
    test(`${operation} database failure propagates as sanitized invocation failure`, async () => {
      const db = new MemoryPromptDb();
      db[operation] = async () => { throw new Error("private database details"); };
      const sender: PromptSender = operation === "failed" ? { send: async () => retry } : new DryRunSender();
      await expect(dispatchDuePrompts({ db, sender, now: () => NOW })).rejects.toThrow("TP_DATABASE_ERROR");
      expect(db.receipts).toHaveLength(0);
    });
  }
  test("database failure drains running workers before returning failure", async () => {
    const db = new MemoryPromptDb(10);
    const sent = db.sent.bind(db);
    let active = 0;
    db.sent = async (claim, ...args) => {
      if (claim.outbox_id === db.rows[0].claim.outbox_id) throw new Error("db unavailable");
      return sent(claim, ...args);
    };
    await expect(dispatchDuePrompts({ db, now: () => NOW, sender: { send: async (delivery) => {
      active++; await Bun.sleep(2); active--; return new DryRunSender().send(delivery);
    } } })).rejects.toThrow("TP_DATABASE_ERROR");
    expect(active).toBe(0);
    expect(db.rows.filter((row) => row.status === "claimed").length).toBeGreaterThan(0);
  });
  test("dry-run sender fails closed on APNs delivery mode", async () => {
    const db = new MemoryPromptDb(); db.rows[0].delivery.mode = "apns";
    expect((await dispatchDuePrompts({ db, sender: new DryRunSender(), now: () => NOW })).failed).toBe(1);
    expect(db.receipts[0].result).toEqual({ accepted: false, error_code: "mode_mismatch", retryable: false, invalidate_device: false });
  });
  test("invalid batch limits fail before claiming", async () => {
    const db = new MemoryPromptDb();
    for (const limit of [0, -1, 101, 1.5, NaN]) {
      await expect(dispatchDuePrompts({ db, sender: new DryRunSender(), now: () => NOW, limit })).rejects.toThrow("TP_INVALID_LIMIT");
    }
    expect(db.calls).toEqual([]);
  });
  test("pure modules contain no network imports, runtime globals or timers", async () => {
    for (const name of ["prompt-dispatch", "prompt-payload", "prompt-strings", "dry-run-sender"]) {
      const source = await Bun.file(new URL(`../_shared/${name}.ts`, import.meta.url)).text();
      expect(source).not.toMatch(/\b(?:Deno|process|fetch|setTimeout|setInterval)\s*[.(]|from\s+["'](?:node:|https?:|npm:|pg["'])/);
    }
  });
});
