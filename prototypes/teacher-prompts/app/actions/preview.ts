"use server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { sameOrigin, secureCookie } from "@/lib/session";
import { ensureDemoDatabase } from "@/lib/db";
import {
  accessCodeMatches,
  previewCookie,
  PREVIEW_COOKIE,
  PREVIEW_TTL,
} from "@/lib/preview";
import { pendingPath, PENDING_COOKIE } from "@/lib/identity";
export async function enterPreview(form: FormData) {
  await sameOrigin();
  await ensureDemoDatabase();
  const next = pendingPath(form.get("next"));
  if (!accessCodeMatches(form.get("code"), process.env.TP_PREVIEW_ACCESS_CODE))
    redirect(
      `/preview?invalid=1${next ? `&next=${encodeURIComponent(next)}` : ""}`,
    );
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
