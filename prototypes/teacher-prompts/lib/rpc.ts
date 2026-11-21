import "server-only";
import { queryAs } from "./db";
import { s } from "./strings";
export const calls = {
  my_lessons_today: ["p_date"],
  lesson_for_prompt: ["p_lesson_id"],
  admin_missing_submissions: ["p_from", "p_until"],
  mark_attendance: [
    "p_lesson_id",
    "p_student_id",
    "p_status",
    "p_absence_informed",
    "p_observed_marked_at",
    "p_expected_revision",
    "p_mutation_id",
  ],
  mark_all_present: ["p_lesson_id", "p_expected_revision", "p_mutation_id"],
  save_feedback: [
    "p_lesson_id",
    "p_body",
    "p_expected_feedback_revision",
    "p_mutation_id",
  ],
  confirm_all_present_and_submit: [
    "p_lesson_id",
    "p_expected_revision",
    "p_expected_feedback_revision",
    "p_mutation_id",
  ],
  submit_lesson: [
    "p_lesson_id",
    "p_expected_revision",
    "p_expected_feedback_revision",
    "p_mutation_id",
  ],
  snooze_prompt: ["p_lesson_id", "p_minutes", "p_mutation_id"],
  simulate_prompt_now: ["p_lesson_id", "p_mutation_id"],
  edit_lesson: ["p_lesson_id", "p_start_at", "p_end_at"],
  assign_lesson_teacher: [
    "p_lesson_id",
    "p_teacher_id",
    "p_keep_previous_as_assistant",
  ],
  cancel_lesson: ["p_lesson_id"],
} as const;
export type Rpc = keyof typeof calls;
export async function rpc<T>(
  identity: string,
  name: Rpc,
  args: Record<string, unknown>,
): Promise<T> {
  if (!Object.hasOwn(calls, name)) throw new Error("TP_INVALID_INPUT");
  const keys = calls[name];
  if (
    Object.keys(args).some((k) => !keys.includes(k as never)) ||
    keys.some((k) => !(k in args))
  )
    throw new Error("TP_INVALID_INPUT");
  try {
    return await queryAs<T>(
      identity,
      `SELECT public.${name}(${keys.map((key, i) => `${key} => $${i + 1}`).join(",")}) AS result`,
      keys.map((key) => args[key]),
    );
  } catch (error) {
    const code =
      error instanceof Error && Object.hasOwn(s.errors, error.message)
        ? error.message
        : "TP_ERROR";
    // Never propagate pg details/context, which can contain SQL arguments.
    throw new Error(code);
  }
}
