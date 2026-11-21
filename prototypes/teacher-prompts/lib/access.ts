import "server-only";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { previewAccessRequired } from "./config";
import { PREVIEW_COOKIE, validPreviewCookie } from "./preview";
export async function requirePreviewAccess() {
  if (
    previewAccessRequired(process.env) &&
    !validPreviewCookie(
      (await cookies()).get(PREVIEW_COOKIE)?.value,
      process.env.TP_PREVIEW_ACCESS_CODE,
    )
  )
    redirect("/preview");
}
