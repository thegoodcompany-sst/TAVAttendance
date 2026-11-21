"use server";
import { revalidatePath } from "next/cache";
import { rpc, type Rpc } from "@/lib/rpc";
import { lessonForPrompt } from "@/lib/queries/lessons";
import { requireIdentity, sameOrigin } from "@/lib/session";
import { uuidPattern } from "@/lib/identity";
import { s } from "@/lib/strings";
import type { Detail, Result } from "@/lib/types";
const writes = new Set<Rpc>([
  "mark_attendance",
  "mark_all_present",
  "save_feedback",
  "submit_lesson",
  "confirm_all_present_and_submit",
  "snooze_prompt",
  "simulate_prompt_now",
  "edit_lesson",
  "assign_lesson_teacher",
  "cancel_lesson",
]);
export async function changeLesson(
  name: Rpc,
  args: Record<string, unknown>,
): Promise<Result<{ detail: Detail; result: Record<string, unknown> }>> {
  try {
    await sameOrigin();
    const identity = await requireIdentity();
    if (
      !writes.has(name) ||
      typeof args.p_lesson_id !== "string" ||
      !uuidPattern.test(args.p_lesson_id)
    )
      throw new Error("TP_INVALID_INPUT");
    const result = await rpc<Record<string, unknown>>(identity.id, name, args);
    const detail = await lessonForPrompt(identity.id, args.p_lesson_id);
    revalidatePath("/");
    revalidatePath("/admin");
    revalidatePath(`/t/lesson/${args.p_lesson_id}`);
    return { ok: true, data: { detail, result } };
  } catch (error) {
    const message = error instanceof Error ? error.message : "";
    return {
      ok: false,
      code: Object.hasOwn(s.errors, message) ? message : "TP_ERROR",
    };
  }
}
export async function refreshLesson(id: string): Promise<Result<Detail>> {
  try {
    await sameOrigin();
    const identity = await requireIdentity();
    return { ok: true, data: await lessonForPrompt(identity.id, id) };
  } catch {
    return { ok: false, code: "TP_NOT_AVAILABLE" };
  }
}
