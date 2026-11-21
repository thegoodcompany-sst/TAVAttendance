"use client";
import { useState, useTransition } from "react";
import { changeLesson } from "@/app/actions/lessons";
import type { Lesson } from "@/lib/types";
import { s } from "@/lib/strings";
import { NotificationBanner } from "./notification-banner";
export function PromptPreview({ lesson }: { lesson: Lesson }) {
  const [visible, setVisible] = useState(false);
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();
  function act(snooze = false) {
    startTransition(async () => {
      setMessage("");
      try {
        const result = await changeLesson(
          snooze ? "snooze_prompt" : "simulate_prompt_now",
          {
            p_lesson_id: lesson.lesson_id,
            p_mutation_id: crypto.randomUUID(),
            ...(snooze ? { p_minutes: 10 } : {}),
          },
        );
        if (result.ok) {
          setVisible(!snooze);
          if (snooze) setMessage(s.snoozed);
        } else
          setMessage(s.errors[result.code as keyof typeof s.errors] ?? s.error);
      } catch {
        setMessage(s.error);
      }
    });
  }
  return (
    <div className="card-preview">
      <button className="text-button" disabled={pending} onClick={() => act()}>
        {s.ping}
      </button>
      {message && (
        <p role="status" className="notice">
          {message}
        </p>
      )}
      {visible && (
        <NotificationBanner
          lessonId={lesson.lesson_id}
          canSnooze={lesson.can_snooze}
          pending={pending}
          close={() => setVisible(false)}
          snooze={() => act(true)}
        />
      )}
    </div>
  );
}
