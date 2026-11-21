"use client";
import { s } from "@/lib/strings";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main className="app-shell">
      <section className="card">
        <h1>{s.error}</h1>
        <button onClick={reset}>{s.retry}</button>
        <a className="button quiet" href="/demo">
          {s.switchAccount}
        </a>
      </section>
    </main>
  );
}
