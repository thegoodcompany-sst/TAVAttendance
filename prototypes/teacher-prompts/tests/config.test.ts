import { Client } from "pg";
import { describe, it, expect, vi } from "vitest";
import { databaseConfig, previewAccessRequired } from "../lib/config";
import {
  accessCodeMatches,
  previewCookie,
  validPreviewCookie,
  PREVIEW_TTL,
} from "../lib/preview";
import { verifyDemoMarker } from "../lib/demo-marker";
const demo = { TEACHER_PROMPTS_DEMO: "1" };
const local = "postgresql://postgres@localhost:55432/tp_unit";
const remote = "postgresql://preview:fake@preview.invalid:5432/tp_unit";
describe("offline database guard", () => {
  it.each([
    {},
    demo,
    { TP_DB: "tp_unit" },
    { ...demo, TEACHER_PROMPTS_DB_NAME: "tp_unit" },
  ])("refuses implicit database or missing demo flag %#", (env) => {
    expect(() => databaseConfig(env)).toThrow();
  });
  it.each(["localhost", "127.0.0.1"])(
    "accepts explicit loopback URL at %s",
    (host) => {
      expect(
        databaseConfig({
          ...demo,
          DATABASE_URL: local.replace("localhost", host),
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
  ])("refuses unsafe URL %s", (DATABASE_URL) =>
    expect(() => databaseConfig({ ...demo, DATABASE_URL })).toThrow(),
  );
  it.each(["", "tp_", "postgres", "tp_Upper", "tp_" + "a".repeat(61)])(
    "refuses invalid assignment %s",
    (TP_DB) => expect(() => databaseConfig({ ...demo, TP_DB })).toThrow(),
  );
  it.each([
    { TP_DB: "tp_other", DATABASE_URL: local },
    {
      TP_DB: "tp_unit",
      DATABASE_URL: local,
      TEACHER_PROMPTS_DB_NAME: "tp_other",
    },
    {
      TP_DB: "tp_unit",
      DATABASE_URL: remote,
      TEACHER_PROMPTS_DATABASE_URL: local,
    },
  ])("refuses inconsistent assignment %#", (env) =>
    expect(() => databaseConfig({ ...demo, ...env })).toThrow(),
  );
  it("accepts runner URL only with an explicit assignment", () => {
    expect(() =>
      databaseConfig({ ...demo, TEACHER_PROMPTS_DATABASE_URL: local }),
    ).toThrow();
    expect(
      databaseConfig({
        ...demo,
        TP_DB: "tp_unit",
        TEACHER_PROMPTS_DATABASE_URL: local,
      }).database,
    ).toBe("tp_unit");
  });
  it.each([
    { ...demo },
    { TP_ALLOW_REMOTE_PREVIEW_DB: "1" },
    { ...demo, TP_ALLOW_REMOTE_PREVIEW_DB: "1" },
    { ...demo, TP_PREVIEW_ACCESS_CODE: "fake-code" },
    { ...demo, TP_ALLOW_REMOTE_PREVIEW_DB: "1", TP_PREVIEW_ACCESS_CODE: " " },
  ])("refuses remote without all three gates %#", (env) =>
    expect(() => databaseConfig({ ...env, DATABASE_URL: remote })).toThrow(),
  );
  it("validates remote preview only with all three gates; never connects", () => {
    const env = {
      ...demo,
      DATABASE_URL: remote,
      TP_ALLOW_REMOTE_PREVIEW_DB: "1",
      TP_PREVIEW_ACCESS_CODE: "fake-code",
    };
    expect(databaseConfig(env)).toMatchObject({
      host: "preview.invalid",
      database: "tp_unit",
      ssl: { rejectUnauthorized: true },
    });
    expect(previewAccessRequired(env)).toBe(true);
    expect(previewAccessRequired({ ...demo, TP_DB: "tp_unit" })).toBe(false);
  });
});
describe("shared preview code", () => {
  it("requires the exact code and never accepts missing configuration", () => {
    expect(accessCodeMatches("fake-code", "fake-code")).toBe(true);
    for (const value of [null, "", "wrong"])
      expect(accessCodeMatches(value, "fake-code")).toBe(false);
    expect(accessCodeMatches("", undefined)).toBe(false);
  });
  it("signs expiring cookies without storing the access code", () => {
    const now = 1700000000000,
      cookie = previewCookie("fake-code", now);
    expect(cookie).not.toContain("fake-code");
    expect(validPreviewCookie(cookie, "fake-code", now)).toBe(true);
    expect(validPreviewCookie(cookie, "changed-code", now)).toBe(false);
    expect(
      validPreviewCookie(cookie, "fake-code", now + PREVIEW_TTL * 1000),
    ).toBe(false);
    expect(validPreviewCookie(cookie, "fake-code", now - 1000)).toBe(false);
    expect(validPreviewCookie(cookie + "x", "fake-code", now)).toBe(false);
    expect(validPreviewCookie(undefined, "fake-code", now)).toBe(false);
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
