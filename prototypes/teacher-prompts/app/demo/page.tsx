import { requirePreviewAccess } from "@/lib/access";
import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { Shell } from "@/components/shell";
import { identities, pendingPath, PENDING_COOKIE } from "@/lib/identity";
import { selectIdentity } from "@/app/actions/identity";
import { s } from "@/lib/strings";
export default async function Demo({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  await requirePreviewAccess();
  const search = await searchParams;
  const jar = await cookies();
  const next = pendingPath(search.next);
  const saved = pendingPath(jar.get(PENDING_COOKIE)?.value);
  if (next && saved !== next)
    redirect(`/demo/capture?next=${encodeURIComponent(next)}`);
  return (
    <Shell>
      <div className="eyebrow">{s.demo}</div>
      <h1>
        {search.failure
          ? s.error
          : search.unavailable
            ? s.unavailable
            : s.identity}
      </h1>
      <p className="muted">
        {search.unavailable ? s.unavailableHelp : s.identityHelp}
      </p>
      {(next || saved) && <p className="notice">{s.pendingRoute}</p>}
      <form action={selectIdentity} className="stack card">
        <input type="hidden" name="next" value={next ?? saved ?? ""} />
        <label htmlFor="identity">{s.selectIdentity}</label>
        <select id="identity" name="identity" defaultValue={identities[4].id}>
          {identities.map((identity) => (
            <option key={identity.id} value={identity.id}>
              {identity.label}
            </option>
          ))}
        </select>
        <button>{s.continue}</button>
      </form>
      <Link className="button quiet" href="/">
        {s.back}
      </Link>
    </Shell>
  );
}
