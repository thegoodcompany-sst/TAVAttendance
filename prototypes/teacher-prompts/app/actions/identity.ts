"use server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import {
  demoIdentity,
  IDENTITY_COOKIE,
  PENDING_COOKIE,
  pendingPath,
} from "@/lib/identity";
import { sameOrigin, secureCookie } from "@/lib/session";
import { lessonForPrompt } from "@/lib/queries/lessons";
export async function selectIdentity(form: FormData) {
  await sameOrigin();
  const identity = demoIdentity(form.get("identity"));
  if (!identity) redirect("/demo");
  const jar = await cookies();
  const options = {
    httpOnly: true,
    sameSite: "lax" as const,
    secure: await secureCookie(),
    path: "/",
    maxAge: 86400,
  };
  jar.set(IDENTITY_COOKIE, identity.id, options);
  const next =
    pendingPath(jar.get(PENDING_COOKIE)?.value) ??
    pendingPath(form.get("next"));
  if (next) {
    jar.set(PENDING_COOKIE, next, options);
    try {
      await lessonForPrompt(identity.id, next.split("/").at(-1)!);
    } catch (error) {
      redirect(
        error instanceof Error && error.message === "TP_NOT_AVAILABLE"
          ? "/demo?unavailable=1"
          : "/demo?failure=1",
      );
    }
    jar.delete(PENDING_COOKIE);
    redirect(next);
  }
  redirect("/");
}
export async function signOut() {
  await sameOrigin();
  const jar = await cookies();
  jar.delete(IDENTITY_COOKIE);
  jar.delete(PENDING_COOKIE);
  redirect("/demo");
}
