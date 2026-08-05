export interface Payload {
  student_id: string;
  status: "present" | "late" | "absent" | "dismissed";
  session_id?: string;
  dismissal_id?: string;
}

export const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Statuses that actually send a parent push (present is intentionally omitted). */
export const NOTIFIABLE_STATUSES = new Set(["late", "absent", "dismissed"]);

/**
 * Validates the JSON body accepted by notify-parent.
 * Returns null for malformed JSON, wrong types, non-UUID ids, or non-notifiable statuses.
 */
export function parsePayload(raw: string): Payload | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  if (
    typeof body.student_id !== "string" || !UUID_PATTERN.test(body.student_id)
  ) return null;
  if (
    typeof body.status !== "string" || !NOTIFIABLE_STATUSES.has(body.status)
  ) return null;
  if (
    body.session_id !== undefined &&
    (typeof body.session_id !== "string" || !UUID_PATTERN.test(body.session_id))
  ) return null;
  if (
    body.dismissal_id !== undefined &&
    (typeof body.dismissal_id !== "string" ||
      !UUID_PATTERN.test(body.dismissal_id))
  ) return null;

  return body as unknown as Payload;
}
