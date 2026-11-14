import { s } from "@/lib/strings";
import { enterPreview } from "@/app/actions/preview";
import { pendingPath } from "@/lib/identity";
export default async function Preview({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const search = await searchParams;
  return (
    <main className="app-shell">
      <h1>{s.previewAccess}</h1>
      <form action={enterPreview} className="card stack">
        <input
          type="hidden"
          name="next"
          value={pendingPath(search.next) ?? ""}
        />
        <label htmlFor="code">{s.accessCode}</label>
        <input
          id="code"
          name="code"
          type="password"
          required
          autoComplete="off"
        />
        {search.invalid && <p role="status">{s.invalidAccessCode}</p>}
        <button>{s.continue}</button>
      </form>
    </main>
  );
}
