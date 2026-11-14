import { Client } from "pg";
import { describe, it, expect, vi } from "vitest";
import { databaseConfig, previewAccessRequired } from "../lib/config";
import {
  accessCodeMatches,
  previewCookie,
  validPreviewCookie,
  PREVIEW_TTL,
} from "../lib/preview";
import { verifyDemoMarker, verifiedDemoPool } from "../lib/demo-marker";
const demo = { TEACHER_PROMPTS_DEMO: "1", TP_DB: "tp_unit" };
const local = "postgresql://postgres@localhost:55432/tp_unit";
const remote =
  "postgresql://preview:fake@preview.invalid:5432/tp_unit?sslmode=require";
describe("offline database guard", () => {
  it.each([
    {},
    { TEACHER_PROMPTS_DEMO: "1" },
    { TP_DB: "tp_unit" },
    { ...demo, TP_DB: undefined, TP_DATABASE_URL: local },
    { ...demo, TP_DB: undefined, TP_DATABASE_URL: remote },
  ])("refuses implicit database or missing demo flag %#", (env) => {
    expect(() => databaseConfig(env)).toThrow();
  });
  it.each(["localhost", "127.0.0.1"])(
    "accepts explicit loopback URL at %s",
    (host) => {
      expect(
        databaseConfig({
          ...demo,
          TP_DATABASE_URL: local.replace("localhost", host),
        }),
      ).toMatchObject({
        host,
        database: "tp_unit",
        password: expect.any(Function),
        options: "-c timezone=Asia/Singapore",
        port: 55432,
        ssl: false,
      });
    },
  );
  it("constructs only the explicit TP_DB and ignores driver environment", () => {
    expect(
      databaseConfig({
        ...demo,
        TP_DB: "tp_unit",
        PGHOST: "remote.invalid",
        PGPASSWORD: "fake",
        PGOPTIONS: "fake",
      }),
    ).toMatchObject({
      host: "localhost",
      database: "tp_unit",
      password: expect.any(Function),
      options: "-c timezone=Asia/Singapore",
    });
  });
  it.each([
    "postgresql://postgres@localhost:5432/tp_unit",
    "postgresql://postgres:fake@localhost:55432/tp_unit",
    "postgresql://other@localhost:55432/tp_unit",
    "postgresql://postgres@localhost:55432/postgres",
    "postgresql://postgres@localhost:55432/tp_UPPER",
    "postgresql://postgres@localhost:55432/tp_x/other",
    local + "?host=remote.invalid",
    local + "#fragment",
    "https://localhost:55432/tp_unit",
    "bad",
  ])("refuses unsafe URL %s", (TP_DATABASE_URL) =>
    expect(() => databaseConfig({ ...demo, TP_DATABASE_URL })).toThrow(),
  );
  it.each(["", "tp_", "postgres", "tp_Upper", "tp_" + "a".repeat(61)])(
    "refuses invalid assignment %s",
    (TP_DB) => expect(() => databaseConfig({ ...demo, TP_DB })).toThrow(),
  );
  it("refuses a mismatched assignment", () => {
    expect(() =>
      databaseConfig({ ...demo, TP_DB: "tp_other", TP_DATABASE_URL: local }),
    ).toThrow("TP_DATABASE_NAME_MISMATCH");
  });
  it("requires TP_DB even with an explicit URL", () => {
    expect(() =>
      databaseConfig({ TEACHER_PROMPTS_DEMO: "1", TP_DATABASE_URL: local }),
    ).toThrow("TP_DATABASE_NOT_ASSIGNED");
  });
  it("never selects generic or obsolete URLs", () => {
    expect(() =>
      databaseConfig({ TEACHER_PROMPTS_DEMO: "1", DATABASE_URL: local }),
    ).toThrow();
    expect(
      databaseConfig({
        ...demo,
        DATABASE_URL: remote,
        TEACHER_PROMPTS_DATABASE_URL: remote,
      }).host,
    ).toBe("localhost");
  });
  it.each([
    { ...demo },
    { TP_ALLOW_REMOTE_PREVIEW_DB: "1" },
    { ...demo, TP_ALLOW_REMOTE_PREVIEW_DB: "1" },
    {
      ...demo,
      TP_PREVIEW_ACCESS_CODE: "fake-code-with-at-least-24-characters",
    },
    { ...demo, TP_ALLOW_REMOTE_PREVIEW_DB: "1", TP_PREVIEW_ACCESS_CODE: " " },
    {
      ...demo,
      TP_ALLOW_REMOTE_PREVIEW_DB: "1",
      TP_PREVIEW_ACCESS_CODE: "x".repeat(23),
    },
  ])("refuses remote without all three gates %#", (env) =>
    expect(() => databaseConfig({ ...env, TP_DATABASE_URL: remote })).toThrow(),
  );
  it("validates remote preview only with all three gates; never connects", () => {
    const env = {
      ...demo,
      TP_DATABASE_URL: remote,
      TP_ALLOW_REMOTE_PREVIEW_DB: "1",
      TP_PREVIEW_ACCESS_CODE: "fake-code-with-at-least-24-characters",
    };
    expect(databaseConfig(env)).toMatchObject({
      host: "preview.invalid",
      database: "tp_unit",
      ssl: { rejectUnauthorized: true },
    });
    expect(previewAccessRequired(env)).toBe(true);
    expect(previewAccessRequired({ ...demo, TP_DB: "tp_unit" })).toBe(false);
  });
  it.each([
    "",
    "?sslmode=disable",
    "?sslmode=no-verify",
    "?sslmode=require&host=other.invalid",
    "?sslmode=require&sslmode=disable",
  ])("rejects remote TLS/options %s without connecting", (query) => {
    expect(() =>
      databaseConfig({
        ...demo,
        TP_DATABASE_URL: remote.split("?")[0] + query,
        TP_ALLOW_REMOTE_PREVIEW_DB: "1",
        TP_PREVIEW_ACCESS_CODE: "x".repeat(24),
      }),
    ).toThrow();
  });
  it("rejects a short configured local gate too", () => {
    expect(() =>
      databaseConfig({ ...demo, TP_PREVIEW_ACCESS_CODE: "short" }),
    ).toThrow("TP_PREVIEW_CODE_REQUIRED");
  });
});
describe("shared preview code", () => {
  it("requires the exact code and never accepts missing configuration", () => {
    expect(
      accessCodeMatches(
        "fake-code-with-at-least-24-characters",
        "fake-code-with-at-least-24-characters",
      ),
    ).toBe(true);
    for (const value of [null, "", "wrong"])
      expect(
        accessCodeMatches(value, "fake-code-with-at-least-24-characters"),
      ).toBe(false);
    expect(accessCodeMatches("", undefined)).toBe(false);
  });
  it("signs expiring cookies without storing the access code", () => {
    const now = 1700000000000,
      cookie = previewCookie("fake-code-with-at-least-24-characters", now);
    expect(cookie).not.toContain("fake-code-with-at-least-24-characters");
    expect(
      validPreviewCookie(cookie, "fake-code-with-at-least-24-characters", now),
    ).toBe(true);
    expect(validPreviewCookie(cookie, "changed-code", now)).toBe(false);
    expect(
      validPreviewCookie(
        cookie,
        "fake-code-with-at-least-24-characters",
        now + PREVIEW_TTL * 1000,
      ),
    ).toBe(false);
    expect(
      validPreviewCookie(
        cookie,
        "fake-code-with-at-least-24-characters",
        now - 1000,
      ),
    ).toBe(false);
    expect(
      validPreviewCookie(
        cookie + "x",
        "fake-code-with-at-least-24-characters",
        now,
      ),
    ).toBe(false);
    expect(
      validPreviewCookie(
        undefined,
        "fake-code-with-at-least-24-characters",
        now,
      ),
    ).toBe(false);
    expect(validPreviewCookie(cookie, undefined, now)).toBe(false);
  });
});
describe("demo marker before serving", () => {
  it.each([true, false, undefined, "error"])(
    "checks service role marker %s and releases",
    async (marker) => {
      const client = {
        query: vi.fn(async (sql: string) => {
          if (sql.startsWith("SELECT") && marker === "error")
            throw new Error("private detail");
          return { rows: [{ demo_enabled: marker }] };
        }),
        release: vi.fn(),
      };
      const pool = { connect: vi.fn().mockResolvedValue(client) };
      if (marker === true)
        await expect(verifyDemoMarker(pool)).resolves.toBeUndefined();
      else
        await expect(verifyDemoMarker(pool)).rejects.toThrow(
          "TP_DEMO_REQUIRED",
        );
      expect(client.query.mock.calls.slice(0, 2)).toEqual([
        ["BEGIN"],
        ["SET LOCAL ROLE service_role"],
      ]);
      expect(client.query).toHaveBeenLastCalledWith(
        marker === true ? "COMMIT" : "ROLLBACK",
      );
      expect(client.release).toHaveBeenCalledOnce();
    },
  );
});

it("pg itself ignores inherited password/options without connecting or reading credential files", () => {
  vi.stubEnv("PGPASSWORD", "fake-inherited-secret");
  vi.stubEnv("PGOPTIONS", "-c search_path=unsafe");
  vi.stubEnv("PGHOST", "remote.invalid");
  vi.stubEnv("PGSSLMODE", "no-verify");
  try {
    const config = databaseConfig({ ...demo, TP_DB: "tp_unit" });
    const client = new Client(config) as unknown as {
      connectionParameters: {
        password: () => string;
        options: string;
        host: string;
        ssl: boolean;
      };
    };
    expect(client.connectionParameters.password()).toBe("");
    expect(client.connectionParameters.options).toBe(
      "-c timezone=Asia/Singapore",
    );
    expect(client.connectionParameters.host).toBe("localhost");
    expect(client.connectionParameters.ssl).toBe(false);
  } finally {
    vi.unstubAllEnvs();
  }
});
it("connection failure cannot expose driver details", async () => {
  await expect(
    verifyDemoMarker({
      connect: vi.fn().mockRejectedValue(new Error("private driver detail")),
    }),
  ).rejects.toThrow("TP_DEMO_REQUIRED");
});

it("keeps a pool private until marker verification resolves", async () => {
  let resolve!: (value: { rows: { demo_enabled: boolean }[] }) => void;
  const marker = new Promise<{ rows: { demo_enabled: boolean }[] }>((done) => {
    resolve = done;
  });
  const client = {
    query: vi.fn((sql: string) =>
      sql.startsWith("SELECT") ? marker : Promise.resolve({ rows: [] }),
    ),
    release: vi.fn(),
  };
  const pool = {
    connect: vi.fn().mockResolvedValue(client),
    end: vi.fn().mockResolvedValue(undefined),
  };
  let exposed = false;
  const pending = verifiedDemoPool(pool).then((result) => {
    exposed = true;
    return result;
  });
  await vi.waitFor(() => expect(client.query).toHaveBeenCalledTimes(3));
  expect(exposed).toBe(false);
  resolve({ rows: [{ demo_enabled: true }] });
  expect(await pending).toBe(pool);
  expect(pool.end).not.toHaveBeenCalled();
});
it.each([false, undefined, "failure"])(
  "closes unverified pool on marker %s",
  async (marker) => {
    const client = {
      query: vi.fn(async (sql: string) => {
        if (sql.startsWith("SELECT") && marker === "failure")
          throw new Error("private");
        return { rows: [{ demo_enabled: marker }] };
      }),
      release: vi.fn(),
    };
    const pool = {
      connect: vi.fn().mockResolvedValue(client),
      end: vi.fn().mockResolvedValue(undefined),
    };
    await expect(verifiedDemoPool(pool)).rejects.toThrow("TP_DEMO_REQUIRED");
    expect(pool.end).toHaveBeenCalledOnce();
  },
);
