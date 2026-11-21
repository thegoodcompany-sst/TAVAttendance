import { redirect } from "next/navigation";
import { Shell } from "@/components/shell";
import { LessonCard } from "@/components/lesson-card";
import { currentIdentity } from "@/lib/session";
import { missingSubmissions } from "@/lib/queries/admin";
import { singaporeDate, time } from "@/lib/format";
import { s } from "@/lib/strings";
export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ from?: string; until?: string }>;
}) {
  const identity = await currentIdentity();
  if (!identity) redirect("/demo");
  const search = await searchParams;
  const until = search.until ?? singaporeDate();
  const from =
    search.from ??
    singaporeDate(
      new Date(new Date(until + "T12:00:00+08:00").getTime() - 7 * 86400000),
    );
  let data;
  try {
    data = await missingSubmissions(identity.id, from, until);
  } catch (error) {
    if (error instanceof Error && error.message === "TP_NOT_AVAILABLE")
      return (
        <Shell>
          <h1>{s.unavailable}</h1>
        </Shell>
      );
    throw new Error("TP_QUERY_FAILED");
  }
  return (
    <Shell>
      <div className="eyebrow">{s.demoAdmin}</div>
      <h1>{s.admin}</h1>
      <form className="card stack">
        <label htmlFor="from">{s.from}</label>
        <input id="from" type="date" name="from" defaultValue={from} />
        <label htmlFor="until">{s.until}</label>
        <input id="until" type="date" name="until" defaultValue={until} />
        <button>{s.filter}</button>
      </form>
      <div className="stack">
        {data.lessons.map((lesson) => (
          <section key={lesson.lesson_id}>
            <LessonCard lesson={lesson} />
            <p className="delivery">
              {s.delivery}: {s.deliveries[lesson.delivery_state]}
              {lesson.last_attempt_at && ` · ${time(lesson.last_attempt_at)}`}
            </p>
          </section>
        ))}
      </div>
      {!data.lessons.length && <p className="empty">{s.noMissing}</p>}
    </Shell>
  );
}
