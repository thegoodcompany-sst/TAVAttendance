import { dispatchDuePrompts } from "../_shared/prompt-dispatch.ts";
import { DryRunSender } from "../_shared/dry-run-sender.ts";
import { describe, expect, test } from "bun:test";
import { createHandler } from "../teacher-prompt-dispatch/index.ts";
import { parseLocalArgs, refreshBeforeDispatch } from "../teacher-prompt-dispatch/local.ts";
import { localDatabaseConfig } from "../_shared/local-db.ts";
import { RpcPromptDb } from "../_shared/prompt-db.ts";
import { RestPromptDb } from "../_shared/rest-db.ts";
import { MemoryPromptDb, NOW, claimFixture, deliveryFixture, uuid } from "./fixtures.ts";

const secret = "fake-invocation-secret-for-tests-only-0001";
const req = (body = "{}", headers: Record<string, string> = {}) => new Request("http://localhost/dispatch", {
  method: "POST", headers: { "x-teacher-prompt-secret": secret, ...headers }, body,
});
describe("Deno handler through injected doubles", () => {
  test("valid empty invocation dispatches dry run and has no cache", async () => {
    const db = new MemoryPromptDb();
    const response = await createHandler({ db, secret, now: () => NOW })(req());
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toEqual({ claimed: 1, accepted: 1, failed: 0, suppressed: 0 });
  });
  test("POST only", async () => {
    const db = new MemoryPromptDb();
    const response = await createHandler({ db, secret })(new Request("http://localhost/dispatch"));
    expect(response.status).toBe(405); expect(response.headers.get("allow")).toBe("POST"); expect(db.calls).toHaveLength(0);
  });
  test("rejects missing/wrong/oversized secret and Authorization before database calls", async () => {
    const db = new MemoryPromptDb(); const handler = createHandler({ db, secret });
    const headerCases: Record<string, string>[] = [{ "x-teacher-prompt-secret": "" }, { "x-teacher-prompt-secret": "wrong" },
      { "x-teacher-prompt-secret": "x".repeat(513) }, { authorization: "Bearer fake" }];
    for (const headers of headerCases) {
      expect((await handler(req("{}", headers))).status).toBe(403);
    }
    expect(db.calls).toHaveLength(0);
  });
  test("unconfigured invocation secret fails closed", async () => {
    expect((await createHandler({ db: new MemoryPromptDb(), secret: "" })(req())).status).toBe(503);
  });
  test("rejects caller clock, recipient, token, mode, non-objects and extra keys", async () => {
    const db = new MemoryPromptDb(); const handler = createHandler({ db, secret });
    for (const body of ['{"now":"2027-01-01"}', '{"recipient_id":"someone"}', '{"token":"fake"}',
      '{"mode":"apns"}', '{"__proto__":{}}', "[]", "null", '""', "1", "{"]) {
      expect((await handler(req(body))).status).toBe(400);
    }
    expect(db.calls).toHaveLength(0);
  });
  test("bounds body by actual bytes, including multibyte text and lying content-length", async () => {
    const db = new MemoryPromptDb(); const handler = createHandler({ db, secret });
    for (const request of [req(" ".repeat(1025)), req("é".repeat(600)), req(" ".repeat(1025), { "content-length": "2" }),
      req("{}", { "content-length": "1025" })]) expect((await handler(request)).status).toBe(400);
    expect(db.calls).toHaveLength(0);
  });
  test("empty body and bounded whitespace object accepted", async () => {
    for (const body of ["", "  {}  ", " ".repeat(1022) + "{}"]) {
      expect((await createHandler({ db: new MemoryPromptDb(0), secret })(req(body))).status).toBe(200);
    }
  });
  test("database error produces sanitized non-success response", async () => {
    const db = new MemoryPromptDb(); db.claim = async () => { throw new Error("sensitive db details"); };
    const response = await createHandler({ db, secret })(req());
    expect(response.status).toBe(503);
    expect(await response.text()).not.toContain("sensitive");
  });
  test("default sender rejects a non-demo APNs delivery without network", async () => {
    const db = new MemoryPromptDb(); db.rows[0].delivery.mode = "apns";
    const response = await createHandler({ db, secret, now: () => NOW })(req());
    expect((await response.json()).failed).toBe(1);
    expect(db.receipts[0].result.accepted).toBe(false);
  });
});

describe("local safety and worker RPC mapping", () => {
  test("only exact assigned passwordless localhost URL is accepted", () => {
    expect(localDatabaseConfig("postgresql://postgres@localhost:55432/tp_b", "tp_b").database).toBe("tp_b");
    for (const url of [undefined, "postgresql://postgres@remote:55432/tp_b", "postgresql://postgres@localhost:5432/tp_b",
      "postgresql://postgres:password@localhost:55432/tp_b", "postgresql://postgres@localhost:55432/tp_a",
      "postgresql://postgres@localhost:55432/tp_b?sslmode=require", "postgresql://postgres@localhost:55432/tp_b#fragment"]) {
      expect(() => localDatabaseConfig(url, "tp_b")).toThrow("TP_LOCAL_DATABASE_REQUIRED");
    }
  });
  test("reserved and malformed database names rejected", () => {
    for (const name of ["postgres", "template0", "template1", "template_custom", "unassigned", "tp_", "a-b", "../tp_b", "x".repeat(64), undefined]) {
      expect(() => localDatabaseConfig(`postgresql://postgres@localhost:55432/${name}`, name)).toThrow("TP_LOCAL_DATABASE_REQUIRED");
    }
  });
  test("refresh failure reports once and permits dispatch and next refresh", async () => {
    const messages: string[] = [];
    let calls = 0;
    const db = { refresh: async () => { calls++; if (calls === 1) throw new Error("private database details"); } };
    await refreshBeforeDispatch(db, (message) => messages.push(message));
    const result = await dispatchDuePrompts({ db: new MemoryPromptDb(0), sender: new DryRunSender(), now: () => NOW });
    expect(result.claimed).toBe(0);
    await refreshBeforeDispatch(db, (message) => messages.push(message));
    expect(calls).toBe(2); expect(messages).toHaveLength(1);
    expect(messages[0]).not.toContain("private");
  });
  test("runner parses once/watch and permits fixed clock only with once", () => {
    expect(parseLocalArgs(["--once"])).toEqual({ watch: false });
    expect(parseLocalArgs(["--watch"])).toEqual({ watch: true });
    expect(parseLocalArgs(["--once", "--now", NOW])).toEqual({ watch: false, fixedNow: NOW });
    for (const args of [[], ["--watch", "--once"], ["--once", "--once"], ["--watch", "--now", NOW],
      ["--once", "--now"], ["--once", "--now", "2027-01-07"], ["--once", "--apns"]]) {
      expect(() => parseLocalArgs(args)).toThrow("TP_INVALID_ARGUMENTS");
    }
  });
  test("adapter maps every RPC argument exactly, preserving decimal revision strings", async () => {
    const calls: unknown[] = []; const claim = claimFixture();
    const db = new RpcPromptDb(async (name, args) => {
      calls.push({ name, args });
      if (name === "scheduler_tick") return [claim];
      if (name === "prepare_prompt_delivery") return deliveryFixture();
      return true;
    });
    expect((await db.claim(NOW, 50))[0].plan_revision).toBe("9007199254740993");
    expect(await db.prepare(claim, NOW)).toEqual(deliveryFixture());
    expect(await db.sent(claim, { accepted: true, provider_id: uuid(1), transport: "dry_run" }, NOW)).toBe(true);
    expect(await db.failed(claim, { accepted: false, error_code: "unregistered", retryable: false, invalidate_device: true }, NOW)).toBe(true);
    expect(calls).toEqual([
      { name: "scheduler_tick", args: { p_now: NOW, p_limit: 50 } },
      { name: "prepare_prompt_delivery", args: { p_outbox_id: claim.outbox_id, p_lease_token: claim.lease_token, p_now: NOW } },
      { name: "mark_prompt_sent", args: { p_outbox_id: claim.outbox_id, p_lease_token: claim.lease_token, p_provider_id: uuid(1), p_transport: "dry_run", p_now: NOW } },
      { name: "mark_prompt_failed", args: { p_outbox_id: claim.outbox_id, p_lease_token: claim.lease_token,
        p_error_code: "unregistered", p_retryable: false, p_invalidate_device: true, p_now: NOW } },
    ]);
  });
  test("hosted adapter uses only injected fake fetch and does not leak provider bodies", async () => {
    let calls = 0;
    const fake = (async (input: string | URL | Request, init?: RequestInit) => {
      calls++; expect(String(input)).toBe("https://example.invalid/rest/v1/rpc/scheduler_tick");
      expect(JSON.parse(init?.body as string)).toEqual({ p_now: NOW, p_limit: 50 });
      return new Response("sensitive SQL details", { status: 500 });
    }) as typeof fetch;
    const db = new RestPromptDb("https://example.invalid", "fake-service-key", fake);
    expect(calls).toBe(0);
    await expect(db.claim(NOW, 50)).rejects.toThrow("TP_DATABASE_ERROR");
    expect(calls).toBe(1);
  });
});
