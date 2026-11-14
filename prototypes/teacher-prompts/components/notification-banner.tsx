"use client";
import Link from "next/link";
import { s } from "@/lib/strings";
import {
  buildPromptPayload,
  lessonPath,
} from "../../../supabase/v2/functions/_shared/prompt-payload";
export function NotificationBanner({
  lessonId,
  canSnooze,
  pending,
  close,
  snooze,
}: {
  lessonId: string;
  canSnooze: boolean;
  pending: boolean;
  close: () => void;
  snooze: () => void;
}) {
  const payload = buildPromptPayload(lessonId, "attendance");
  return (
    <aside
      className="notification"
      aria-label={s.preview}
      data-testid="notification"
    >
      <div className="notification-top">
        <span className="app-icon" aria-hidden>
          ✓
        </span>
        <strong>{payload.aps.alert.title}</strong>
        <span>{s.now}</span>
        <button className="close quiet" aria-label={s.close} onClick={close}>
          ×
        </button>
      </div>
      <Link
        href={lessonPath(lessonId)}
        className="notification-body"
        onClick={close}
      >
        <strong>{payload.aps.alert.body}</strong>
        <span>{s.preview}</span>
      </Link>
      <div className="notification-actions">
        <Link href={lessonPath(lessonId)} onClick={close}>
          {s.takeAttendance}
        </Link>
        <button
          className="text-button"
          disabled={pending || !canSnooze}
          onClick={snooze}
        >
          {s.remind}
        </button>
      </div>
    </aside>
  );
}
