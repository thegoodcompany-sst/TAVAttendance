import Link from "next/link";
import { time, day } from "@/lib/format";
import type { Lesson } from "@/lib/types";
import { s } from "@/lib/strings";
export function LessonCard({ lesson }: { lesson: Lesson }) {
  return (
    <Link href={`/t/lesson/${lesson.lesson_id}`} className="lesson-card card">
      <div className="row">
        <span className={`pill ${lesson.state}`}>{s.states[lesson.state]}</span>
        <span className="arrow" aria-hidden>
          ↗
        </span>
      </div>
      <h3>{lesson.class_label}</h3>
      <p>
        {day(lesson.scheduled_start_at)} · {time(lesson.scheduled_start_at)}–
        {time(lesson.scheduled_end_at)}
      </p>
      <div className="card-bottom">
        <span>{lesson.accountable_teacher_label}</span>
        <strong>
          {lesson.marked_count}/{lesson.roster_count} {s.progress}
        </strong>
      </div>
      <div className="progress-track">
        <span
          style={{
            width: `${lesson.roster_count ? (lesson.marked_count / lesson.roster_count) * 100 : 0}%`,
          }}
        />
      </div>
    </Link>
  );
}
