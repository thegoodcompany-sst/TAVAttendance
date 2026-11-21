import { promptStrings } from "./prompt-strings.ts";

export type PromptKind = keyof typeof promptStrings.bodies;
export const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function validateLesson(lessonId: string): void {
  if (typeof lessonId !== "string" || !UUID_PATTERN.test(lessonId)) {
    throw new Error("TP_INVALID_LESSON_ID");
  }
}

export function lessonPath(lessonId: string): string {
  validateLesson(lessonId);
  return `/t/lesson/${lessonId}`;
}

export function buildPromptPayload(lessonId: string, kind: PromptKind) {
  validateLesson(lessonId);
  if (!Object.hasOwn(promptStrings.bodies, kind)) throw new Error("TP_INVALID_KIND");
  return {
    aps: {
      alert: { title: promptStrings.title, body: promptStrings.bodies[kind] },
      sound: "default",
      category: "TAVA_TEACHER_PROMPT",
      "thread-id": `teacher-lesson:${lessonId}`,
    },
    v: 1,
    type: "teacher_prompt",
    lesson_id: lessonId,
    kind,
  } as const;
}
