import Link from "next/link";
import { redirect } from "next/navigation";
import { Shell } from "@/components/shell";
import { PromptPreview } from "@/components/prompt-preview";
import { LessonCard } from "@/components/lesson-card";
import { currentIdentity } from "@/lib/session";
import { myLessons } from "@/lib/queries/lessons";
import { s } from "@/lib/strings";
export default async function TodayPage({
  searchParams,
}: {
  searchParams: Promise<{ date?: string }>;
}) {
  const identity = await currentIdentity();
  if (!identity) redirect("/demo");
  const { date } = await searchParams;
  const data = await myLessons(identity.id, date ?? null);
  return (
    <Shell>
      <div className="eyebrow">{s.review}</div>
      <h1>{s.today}</h1>
      <div className="summary">
        <strong>{data.outstanding_count}</strong>
        <span>{s.outstanding}</span>
        <span className="summary-symbol" aria-hidden>
          ✓
        </span>
      </div>
      <form className="date-form">
        <label htmlFor="date">{s.date}</label>
        <div className="row">
          <input id="date" type="date" name="date" defaultValue={data.date} />
          <button className="quiet">{s.show}</button>
        </div>
      </form>
      <div className="stack">
        {data.lessons.map((lesson) => (
          <section key={lesson.lesson_id}>
            <LessonCard lesson={lesson} />
            {lesson.state !== "submitted" && lesson.state !== "cancelled" && (
              <PromptPreview
                key={`${identity.id}:${lesson.lesson_id}`}
                lesson={lesson}
              />
            )}
          </section>
        ))}
        {!data.lessons.length && <p className="empty">{s.empty}</p>}
      </div>
      <h2>{s.backlog}</h2>
      <div className="stack">
        {data.backlog.map((lesson) => (
          <LessonCard key={lesson.lesson_id} lesson={lesson} />
        ))}
        {!data.backlog.length && <p className="muted">{s.emptyBacklog}</p>}
      </div>
      <p className="muted small">{s.noDevices}</p>
      {identity.id.endsWith("000001") && (
        <Link className="button quiet" href="/admin">
          {s.admin}
        </Link>
      )}
    </Shell>
  );
}
