"use client";
import Link from "next/link";
import { useState, useTransition } from "react";
import { changeLesson, refreshLesson } from "@/app/actions/lessons";
import { identities, nextStatus } from "@/lib/identity";
import { s } from "@/lib/strings";
import { day, time, localInput } from "@/lib/format";
import type { Detail, Student, Status } from "@/lib/types";
import type { Rpc } from "@/lib/rpc";
import { NotificationBanner } from "./notification-banner";
export function LessonReview({
  initial,
  admin,
}: {
  initial: Detail;
  admin: boolean;
}) {
  const [data, setData] = useState(initial);
  const [draft, setDraft] = useState(initial.feedback.body);
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();
  const [confirmAll, setConfirmAll] = useState(false);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [notification, setNotification] = useState(false);
  const lesson = data.lesson;
  const remaining = lesson.roster_count - lesson.marked_count;
  const dirty = draft !== data.feedback.body;
  function run(name: Rpc, args: Record<string, unknown>, success?: () => void) {
    setMessage("");
    startTransition(async () => {
      try {
        const result = await changeLesson(name, {
          p_lesson_id: lesson.lesson_id,
          ...args,
        });
        if (result.ok) {
          setData(result.data.detail);
          success?.();
        } else {
          setMessage(s.errors[result.code as keyof typeof s.errors] ?? s.error);
          if (result.code === "TP_CONFLICT") {
            const fresh = await refreshLesson(lesson.lesson_id);
            if (fresh.ok) setData(fresh.data);
            setMessage(s.stale);
          }
        }
      } catch {
        setMessage(s.error);
      }
    });
  }
  const mutation = () => crypto.randomUUID();
  function mark(
    student: Student,
    status: Status,
    informed: boolean | null = null,
  ) {
    run("mark_attendance", {
      p_student_id: student.student_id,
      p_status: status,
      p_absence_informed: informed,
      p_observed_marked_at: student.marked_at,
      p_expected_revision: lesson.register_revision,
      p_mutation_id: mutation(),
    });
  }
  function snooze() {
    run("snooze_prompt", { p_minutes: 10, p_mutation_id: mutation() }, () => {
      setMessage(s.snoozed);
      setNotification(false);
    });
  }
  return (
    <>
      <Link className="back-link" href="/">
        ← {s.back}
      </Link>
      {notification && (
        <NotificationBanner
          lessonId={lesson.lesson_id}
          canSnooze={lesson.can_snooze}
          pending={pending}
          close={() => setNotification(false)}
          snooze={snooze}
        />
      )}
      <div className="lesson-heading">
        <span className={`pill ${lesson.state}`}>{s.states[lesson.state]}</span>
        <h1>{lesson.class_label}</h1>
        <p>
          {day(lesson.scheduled_start_at)} · {time(lesson.scheduled_start_at)}–
          {time(lesson.scheduled_end_at)}
        </p>
        <span className="muted">{lesson.accountable_teacher_label}</span>
      </div>
      {data.submission && (
        <section className="done-panel" data-testid="done">
          <span className="done-icon" aria-hidden>
            ✓
          </span>
          <h2>{s.done}</h2>
          <p>{s.doneHelp}</p>
          <p className="small">{s.submitNotice}</p>
          <Link href="/" className="button">
            {s.back}
          </Link>
        </section>
      )}
      {lesson.state === "cancelled" && <p className="notice">{s.cancelled}</p>}
      {message && (
        <div className="notice" role="status">
          {message}
        </div>
      )}
      {!data.submission && lesson.state !== "cancelled" && (
        <section className="reminder-card">
          <button
            className="quiet"
            disabled={pending}
            onClick={() =>
              run("simulate_prompt_now", { p_mutation_id: mutation() }, () =>
                setNotification(true),
              )
            }
          >
            {s.ping}
          </button>
          <button
            className="text-button"
            disabled={pending || !lesson.can_snooze}
            onClick={snooze}
          >
            {s.remind}
          </button>
          <p>
            {lesson.next_prompt_at ? (
              <>
                {s.nextPrompt} · {day(lesson.next_prompt_at)} ·{" "}
                {time(lesson.next_prompt_at)}
              </>
            ) : (
              s.noPrompt
            )}
          </p>
        </section>
      )}
      <section className="attendance-section">
        <div className="section-heading">
          <h2>{s.attendance}</h2>
          <span className="count">
            {lesson.marked_count}/{lesson.roster_count}
          </span>
        </div>
        <div className="progress-track">
          <span
            style={{
              width: `${lesson.roster_count ? (100 * lesson.marked_count) / lesson.roster_count : 0}%`,
            }}
          />
        </div>
        {lesson.can_edit ? (
          <>
            <p className="muted small">{s.cycleHint}</p>
            <button
              className="quiet full"
              disabled={pending || remaining === 0}
              onClick={() => setConfirmAll(true)}
            >
              {s.allPresent}
            </button>
          </>
        ) : (
          <p className="muted">{s.readOnly}</p>
        )}
        {confirmAll && (
          <section
            className="notice stack"
            role="dialog"
            aria-label={s.confirmAll}
          >
            <strong>{s.confirmAll}</strong>
            <p>{s.confirmAllHelp}</p>
            <div className="row">
              <button
                disabled={pending}
                onClick={() =>
                  run(
                    "mark_all_present",
                    {
                      p_expected_revision: lesson.register_revision,
                      p_mutation_id: mutation(),
                    },
                    () => setConfirmAll(false),
                  )
                }
              >
                {s.confirm}
              </button>
              <button className="quiet" onClick={() => setConfirmAll(false)}>
                {s.cancel}
              </button>
            </div>
          </section>
        )}
        <ul className="roster">
          {data.roster.map((student, index) => (
            <li
              key={student.student_id}
              className="student"
              data-testid="student"
            >
              <div className="student-main">
                <span className="avatar" aria-hidden>
                  {String(index + 1).padStart(2, "0")}
                </span>
                <div className="student-name">
                  <strong>{student.display_name}</strong>
                  {student.status && lesson.can_edit && (
                    <button
                      className="text-button clear"
                      disabled={pending}
                      onClick={() => mark(student, null)}
                      aria-label={`${s.clear} ${student.display_name}`}
                    >
                      {s.clear}
                    </button>
                  )}
                </div>
                <button
                  className={`status ${student.status ?? "unmarked"}`}
                  aria-label={`${student.display_name}: ${student.status ? s[student.status] : s.notMarked}`}
                  disabled={pending || !lesson.can_edit}
                  onClick={() => mark(student, nextStatus(student.status))}
                >
                  {student.status ? s[student.status] : s.notMarked}
                </button>
              </div>
              {student.status === "absent" && (
                <label className="informed">
                  <input
                    type="checkbox"
                    checked={student.absence_informed === true}
                    disabled={pending || !lesson.can_edit}
                    onChange={(event) =>
                      mark(student, "absent", event.target.checked)
                    }
                  />
                  {s.informed}
                </label>
              )}
            </li>
          ))}
        </ul>
      </section>
      <section className="notes card">
        <div className="section-heading">
          <label htmlFor="notes">{s.notes}</label>
          <span className="muted small">{s.optional}</span>
        </div>
        <p id="notes-help" className="muted small">
          {s.notesHelp}
        </p>
        <textarea
          id="notes"
          maxLength={1000}
          rows={4}
          aria-describedby="notes-help"
          value={draft}
          disabled={pending || !lesson.can_edit}
          onChange={(event) => setDraft(event.target.value)}
        />
        <div className="row">
          <span className="muted small">{draft.length}/1000</span>
          {lesson.can_edit && (
            <button
              className="quiet"
              disabled={pending || !dirty}
              onClick={() =>
                run(
                  "save_feedback",
                  {
                    p_body: draft,
                    p_expected_feedback_revision: data.feedback.revision,
                    p_mutation_id: mutation(),
                  },
                  () => {
                    setDraft(draft.trim());
                    setMessage(s.savedNotes);
                  },
                )
              }
            >
              {s.saveNotes}
            </button>
          )}
        </div>
      </section>
      {!data.submission && lesson.state !== "cancelled" && (
        <section className="submit-panel">
          <p>{remaining ? `${remaining} ${s.remaining}` : s.confirmSubmit}</p>
          <button
            className="full"
            disabled={pending || remaining > 0 || dirty || !lesson.can_submit}
            onClick={() =>
              run(
                "submit_lesson",
                {
                  p_expected_revision: lesson.register_revision,
                  p_expected_feedback_revision: data.feedback.revision,
                  p_mutation_id: mutation(),
                },
                () => setNotification(false),
              )
            }
          >
            {pending ? s.saving : s.submit}
          </button>
          <p className="muted small">{dirty ? s.saveNotes : s.submitNotice}</p>
        </section>
      )}
      {admin && !data.submission && lesson.state !== "cancelled" && (
        <details className="card admin-tools">
          <summary>{s.adminTools}</summary>
          <form
            className="stack"
            action={(form) => {
              run(
                "edit_lesson",
                {
                  p_start_at: new Date(
                    `${form.get("start")}:00+08:00`,
                  ).toISOString(),
                  p_end_at: new Date(
                    `${form.get("end")}:00+08:00`,
                  ).toISOString(),
                },
                () => setMessage(s.updated),
              );
            }}
          >
            <label htmlFor="start">{s.start}</label>
            <input
              type="datetime-local"
              name="start"
              id="start"
              required
              defaultValue={localInput(lesson.scheduled_start_at)}
            />
            <label htmlFor="end">{s.end}</label>
            <input
              type="datetime-local"
              name="end"
              id="end"
              required
              defaultValue={localInput(lesson.scheduled_end_at)}
            />
            <button className="quiet" disabled={pending}>
              {s.editSchedule}
            </button>
          </form>
          <form
            className="stack"
            action={(form) =>
              run(
                "assign_lesson_teacher",
                {
                  p_teacher_id: form.get("teacher"),
                  p_keep_previous_as_assistant: false,
                },
                () => setMessage(s.updated),
              )
            }
          >
            <label htmlFor="teacher">{s.substitute}</label>
            <select
              name="teacher"
              id="teacher"
              defaultValue={lesson.accountable_teacher_id}
            >
              {identities.slice(1, 5).map((identity) => (
                <option key={identity.id} value={identity.id}>
                  {identity.label}
                </option>
              ))}
            </select>
            <button className="quiet" disabled={pending}>
              {s.assign}
            </button>
          </form>
          <button
            className="quiet full"
            disabled={pending}
            onClick={() => setConfirmCancel(true)}
          >
            {s.cancelLesson}
          </button>
          {confirmCancel && (
            <div
              className="notice stack"
              role="dialog"
              aria-label={s.confirmCancel}
            >
              <strong>{s.confirmCancel}</strong>
              <button
                disabled={pending}
                onClick={() =>
                  run("cancel_lesson", {}, () => setConfirmCancel(false))
                }
              >
                {s.confirm}
              </button>
              <button className="quiet" onClick={() => setConfirmCancel(false)}>
                {s.cancel}
              </button>
            </div>
          )}
        </details>
      )}
    </>
  );
}
