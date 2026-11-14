import { describe, it, expect } from "vitest";
import {
  demoIdentity,
  identities,
  pendingPath,
  nextStatus,
} from "../lib/identity";
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
describe("Singapore time", () => {
  it("changes civil date at UTC 16:00", () => {
    expect(singaporeDate(new Date("2027-01-07T15:59:00Z"))).toBe("2027-01-07");
    expect(singaporeDate(new Date("2027-01-07T16:00:00Z"))).toBe("2027-01-08");
    expect(time("2027-01-07T13:00:00Z")).toMatch(/9:00/);
  });
});
