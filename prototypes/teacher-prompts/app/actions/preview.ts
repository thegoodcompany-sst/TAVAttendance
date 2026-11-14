"use server";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { sameOrigin, secureCookie } from "@/lib/session";
import { ensureDemoDatabase } from "@/lib/db";
import {
  accessCodeMatches,
  previewCookie,
  PREVIEW_COOKIE,
  PREVIEW_TTL,
} from "@/lib/preview";
import { previewAttempts, previewClientIp } from "@/lib/preview-attempts";
import { pendingPath, PENDING_COOKIE } from "@/lib/identity";
export async function enterPreview(form: FormData) {
  await sameOrigin();
  const retry = previewAttempts.take(
    previewClientIp(
      await headers(),
      process.env.TP_TRUST_PREVIEW_PROXY === "1",
    ),
  );
  const next = pendingPath(form.get("next"));
  if (
    retry ||
    !accessCodeMatches(form.get("code"), process.env.TP_PREVIEW_ACCESS_CODE)
  )
    redirect(
      `/preview?invalid=1${retry ? `&retry=${retry}` : ""}${next ? `&next=${encodeURIComponent(next)}` : ""}`,
    );
  await ensureDemoDatabase();
  const jar = await cookies();
  const secure = await secureCookie();
  jar.set(PREVIEW_COOKIE, previewCookie(process.env.TP_PREVIEW_ACCESS_CODE!), {
    httpOnly: true,
    sameSite: "lax",
    secure,
    path: "/",
    maxAge: PREVIEW_TTL,
  });
  if (next)
    jar.set(PENDING_COOKIE, next, {
      httpOnly: true,
      sameSite: "lax",
      secure,
      path: "/",
      maxAge: 86400,
    });
  redirect(next ? `/demo?next=${encodeURIComponent(next)}` : "/demo");
}
