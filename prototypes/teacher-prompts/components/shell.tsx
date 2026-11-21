import Link from "next/link";
import { Theme } from "./theme";
import { s } from "@/lib/strings";
import { currentIdentity } from "@/lib/session";
import { signOut } from "@/app/actions/identity";
export async function Shell({ children }: { children: React.ReactNode }) {
  const identity = await currentIdentity();
  return (
    <div className="app-shell">
      <header>
        <Link href="/" className="brand">
          {s.brand}
          <span className="brand-dot" />
        </Link>
        <Theme />
      </header>
      <div className="account">
        <span>{identity?.label ?? s.signedOut}</span>
        <Link href="/demo">{s.switchAccount}</Link>
      </div>
      <main>{children}</main>
      <footer>
        <span>{s.demo}</span>
        {identity && (
          <form action={signOut}>
            <button className="text-button">{s.signOut}</button>
          </form>
        )}
      </footer>
    </div>
  );
}
