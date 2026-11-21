import { describe, it, expect, vi, beforeEach } from "vitest";
import { asIdentity, type Client } from "../lib/transaction";
import { identities } from "../lib/identity";
vi.mock("../lib/db", () => ({ queryAs: vi.fn() }));
import { queryAs } from "../lib/db";
import { rpc } from "../lib/rpc";
const makeClient = () => ({
  query: vi.fn().mockResolvedValue({}),
  release: vi.fn(),
});
beforeEach(() => vi.clearAllMocks());
describe("per-request RLS", () => {
  it("sets transaction-local role and only allowlisted claims, then commits/releases", async () => {
    const client = makeClient();
    const result = await asIdentity(client, identities[4].id, async () => 42);
    expect(result).toBe(42);
    expect(client.query.mock.calls).toEqual([
      ["BEGIN"],
      ["SET LOCAL ROLE authenticated"],
      [
        "SELECT set_config('request.jwt.claims', $1, true)",
        [JSON.stringify({ sub: identities[4].id, role: "authenticated" })],
      ],
      ["COMMIT"],
    ]);
    expect(client.release).toHaveBeenCalledOnce();
  });
  it("rolls back and releases on failed work", async () => {
    const client = makeClient();
    await expect(
      asIdentity(client, identities[0].id, async () => {
        throw new Error("TP_CONFLICT");
      }),
    ).rejects.toThrow("TP_CONFLICT");
    expect(client.query).toHaveBeenLastCalledWith("ROLLBACK");
    expect(client.release).toHaveBeenCalledOnce();
  });
  it("does not execute work for forged identity", async () => {
    const client = makeClient();
    const work = vi.fn();
    await expect(asIdentity(client, "forged", work)).rejects.toThrow(
      "TP_NOT_AVAILABLE",
    );
    expect(work).not.toHaveBeenCalled();
    expect(client.release).toHaveBeenCalledOnce();
  });
  it("isolates simultaneous identities on distinct clients", async () => {
    const a = makeClient(),
      b = makeClient();
    await Promise.all([
      asIdentity(a, identities[1].id, async () => 1),
      asIdentity(b, identities[2].id, async () => 2),
    ]);
    expect(JSON.stringify(a.query.mock.calls)).not.toContain(identities[2].id);
    expect(JSON.stringify(b.query.mock.calls)).not.toContain(identities[1].id);
  });
  it("releases even if rollback fails", async () => {
    const client: Client = {
      query: vi.fn().mockRejectedValue(new Error("offline")),
      release: vi.fn(),
    };
    await expect(
      asIdentity(client, identities[1].id, async () => 1),
    ).rejects.toThrow();
    expect(client.release).toHaveBeenCalledOnce();
  });
});
describe("RPC boundary", () => {
  it("uses parameterized values and fixed SQL identifiers", async () => {
    vi.mocked(queryAs).mockResolvedValue({});
    await rpc(identities[1].id, "lesson_for_prompt", {
      p_lesson_id: "'; DROP TABLE students;--",
    });
    expect(queryAs).toHaveBeenCalledWith(
      identities[1].id,
      "SELECT public.lesson_for_prompt(p_lesson_id => $1) AS result",
      ["'; DROP TABLE students;--"],
    );
  });
  it("rejects unknown RPCs before SQL", async () => {
    await expect(rpc(identities[1].id, "unsafe" as never, {})).rejects.toThrow(
      "TP_INVALID_INPUT",
    );
    expect(queryAs).not.toHaveBeenCalled();
  });
  it("rejects missing or extra args including actor/time spoofing", async () => {
    for (const args of [
      {},
      { p_lesson_id: "x", p_actor_id: identities[0].id },
      { p_lesson_id: "x", p_now: "2027-01-01" },
    ])
      await expect(
        rpc(identities[1].id, "lesson_for_prompt", args),
      ).rejects.toThrow();
  });
  it("propagates query failures instead of returning an empty list", async () => {
    vi.mocked(queryAs).mockRejectedValue(new Error("TP_DISABLED"));
    await expect(
      rpc(identities[1].id, "my_lessons_today", { p_date: null }),
    ).rejects.toThrow("TP_DISABLED");
  });
});
it("sanitizes database details and unknown messages before framework logging", async () => {
  const raw = Object.assign(
    new Error("invalid input containing private data"),
    { detail: "private SQL argument", where: "internal query" },
  );
  vi.mocked(queryAs).mockRejectedValue(raw);
  let caught: unknown;
  try {
    await rpc(identities[1].id, "my_lessons_today", { p_date: null });
  } catch (error) {
    caught = error;
  }
  expect(caught).toBeInstanceOf(Error);
  expect((caught as Error).message).toBe("TP_ERROR");
  expect(caught).not.toHaveProperty("detail");
  expect(caught).not.toHaveProperty("where");
});
