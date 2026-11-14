import { describe, expect, test } from "bun:test";
import { buildPromptPayload, lessonPath, type PromptKind } from "../_shared/prompt-payload.ts";
import { promptStrings } from "../_shared/prompt-strings.ts";
import { uuid } from "./fixtures.ts";

describe("generic prompt payload", () => {
  for (const kind of ["heads_up", "attendance", "follow_up", "final"] as const) {
    test(`${kind}: exact keys, centralized copy, privacy and byte limit`, () => {
      const lessonId = uuid(200);
      const payload = buildPromptPayload(lessonId, kind);
      expect(payload).toEqual({
        aps: { alert: { title: "TAVA", body: promptStrings.bodies[kind] }, sound: "default",
          category: "TAVA_TEACHER_PROMPT", "thread-id": `teacher-lesson:${lessonId}` },
        v: 1, type: "teacher_prompt", lesson_id: lessonId, kind,
      });
      const body = JSON.stringify(payload);
      expect(new TextEncoder().encode(body).byteLength).toBeLessThan(4096);
      expect(body).not.toMatch(/student|teacher_name|class_label|token|feedback|badge|https?:|@/);
      expect(lessonPath(lessonId)).toBe(`/t/lesson/${lessonId}`);
    });
  }
  test("all bodies match the agreed stand-in copy", () => {
    expect(promptStrings.bodies).toEqual({ heads_up: "Your lesson ends soon.", attendance: "Please take attendance.",
      follow_up: "Please review your lesson.", final: "Your lesson is waiting for review." });
  });
  for (const invalid of ["", "Demo Student 01", "../lesson", `${uuid(1)}?token=private`, `${uuid(1)}\n`,
    "https://example.invalid/lesson", "ABCDEFAB-0000-4000-8000-000000000001", null, {}, 1]) {
    test(`rejects malformed locator ${JSON.stringify(invalid)}`, () => {
      expect(() => buildPromptPayload(invalid as string, "attendance")).toThrow("TP_INVALID_LESSON_ID");
      expect(() => lessonPath(invalid as string)).toThrow("TP_INVALID_LESSON_ID");
    });
  }
  test("rejects simulation/arbitrary/prototype kind", () => {
    for (const kind of ["simulation", "constructor", "__proto__", "Demo Student 01"]) {
      expect(() => buildPromptPayload(uuid(1), kind as PromptKind)).toThrow("TP_INVALID_KIND");
    }
  });
  test("extra input data cannot spread into a payload", () => {
    const input = { lesson_id: uuid(1), kind: "attendance" as const, student_name: "Demo Student 01", token: "private", class_label: "Demo" };
    expect(JSON.stringify(buildPromptPayload(input.lesson_id, input.kind))).not.toMatch(/Demo|private|student_name|class_label/);
  });
});
