import "server-only";
import { rpc } from "../rpc";
import type { Detail, Today } from "../types";
export const lessonForPrompt = (id: string, lessonId: string) =>
  rpc<Detail>(id, "lesson_for_prompt", { p_lesson_id: lessonId });
export const myLessons = (id: string, date: string | null = null) =>
  rpc<Today>(id, "my_lessons_today", { p_date: date });
