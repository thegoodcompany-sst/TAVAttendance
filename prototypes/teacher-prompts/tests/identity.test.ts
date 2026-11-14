import { describe, it, expect } from "vitest";
import {
  demoIdentity,
  identities,
  pendingPath,
  nextStatus,
} from "../lib/identity";
import { databaseConfig } from "../lib/config";
import { singaporeDate, time } from "../lib/format";
const lesson = "/t/lesson/10000000-0000-4000-8000-000000000001";
describe("demo identity and pending routes", () => {
  it("accepts only seeded identities", () => {
    expect(demoIdentity(identities[4].id)?.label).toBe("Demo Teacher D");
    for (const value of [
      null,
      "admin",
      "10000000-0000-4000-8000-000000000100",
      {},
      "",
    ])
      expect(demoIdentity(value)).toBeNull();
  });
  it("keeps exactly one relative UUID lesson path", () =>
    expect(pendingPath(lesson)).toBe(lesson));
  it.each([
    "https://example.com" + lesson,
    "//example.com" + lesson,
    lesson + "?token=a",
    lesson + "#x",
    lesson + "/",
    lesson + "/extra",
    "/admin",
    "/t/lesson/%2f",
    "/t/lesson/AAAAAAAA-0000-4000-8000-000000000001",
    "/t/lesson/../../admin",
    lesson + "\n",
  ])("rejects unsafe next %s", (value) =>
    expect(pendingPath(value)).toBeNull(),
  );
  it("cycles three real statuses and never invents absence on an empty row", () => {
    expect(nextStatus(null)).toBe("present");
    expect(nextStatus("present")).toBe("late");
    expect(nextStatus("late")).toBe("absent");
    expect(nextStatus("absent")).toBe("present");
  });
});
describe("database startup guard", () => {
  it("defaults only to assigned local tp_c", () =>
    expect(databaseConfig({}).connectionString).toBe(
      "postgresql://postgres@localhost:55432/tp_c",
    ));
  it.each([
    "postgresql://postgres@remote.invalid:55432/tp_c",
    "postgresql://postgres@localhost:5432/tp_c",
    "postgresql://postgres@localhost:55432/tp_a",
    "postgresql://postgres:secret@localhost:55432/tp_c",
    "postgresql://postgres@localhost:55432/tp_c?host=remote.invalid",
    "https://localhost:55432/tp_c",
  ])("rejects unsafe configuration without connecting %s", (url) =>
    expect(() => databaseConfig({ DATABASE_URL: url })).toThrow(),
  );
  it("requires explicit remote preview opt-in (validation only)", () =>
    expect(
      databaseConfig({
        DATABASE_URL: "postgresql://preview.invalid/demo",
        TP_ALLOW_REMOTE_PREVIEW_DB: "1",
      }).connectionString,
    ).toBe("postgresql://preview.invalid/demo"));
  it("matches runner database name", () =>
    expect(() =>
      databaseConfig({ TEACHER_PROMPTS_DB_NAME: "tp_a" }),
    ).toThrow());
});
describe("Singapore time", () => {
  it("changes civil date at UTC 16:00", () => {
    expect(singaporeDate(new Date("2027-01-07T15:59:00Z"))).toBe("2027-01-07");
    expect(singaporeDate(new Date("2027-01-07T16:00:00Z"))).toBe("2027-01-08");
    expect(time("2027-01-07T13:00:00Z")).toMatch(/9:00/);
  });
});
