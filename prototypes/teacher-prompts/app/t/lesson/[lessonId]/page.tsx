import Link from "next/link";
import { redirect } from "next/navigation";
import { Shell } from "@/components/shell";
import { LessonReview } from "@/components/lesson-review";
import { lessonForPrompt } from "@/lib/queries/lessons";
import { currentIdentity } from "@/lib/session";
import { uuidPattern } from "@/lib/identity";
import { s } from "@/lib/strings";
export default async function LessonPage({
  params,
}: {
  params: Promise<{ lessonId: string }>;
}) {
  const { lessonId } = await params;
  const identity = await currentIdentity();
  if (!identity && uuidPattern.test(lessonId))
    redirect(`/demo?next=${encodeURIComponent(`/t/lesson/${lessonId}`)}`);
  let detail;
  try {
    if (!identity || !uuidPattern.test(lessonId))
      throw new Error("TP_NOT_AVAILABLE");
    detail = await lessonForPrompt(identity.id, lessonId);
  } catch (error) {
    if (error instanceof Error && error.message !== "TP_NOT_AVAILABLE")
      throw new Error("TP_QUERY_FAILED");
    return (
      <Shell>
        <section className="card">
          <h1>{s.unavailable}</h1>
          <p>{s.unavailableHelp}</p>
          <Link
            className="button"
            href={`/demo?next=${encodeURIComponent(`/t/lesson/${lessonId}`)}`}
          >
            {s.switchAccount}
          </Link>
          <Link className="button quiet" href="/">
            {s.back}
          </Link>
        </section>
      </Shell>
    );
  }
  return (
    <Shell>
      <LessonReview
        key={`${identity!.id}:${lessonId}`}
        initial={detail}
        admin={identity!.id.endsWith("000001")}
      />
    </Shell>
  );
}
