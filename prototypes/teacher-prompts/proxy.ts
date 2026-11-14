import { NextRequest, NextResponse } from "next/server";
import { previewAccessRequired } from "./lib/config";
import { PREVIEW_COOKIE, validPreviewCookie } from "./lib/preview";
import { pendingPath } from "./lib/identity";
export function proxy(request: NextRequest) {
  if (
    previewAccessRequired(process.env) &&
    request.nextUrl.pathname !== "/preview" &&
    !validPreviewCookie(
      request.cookies.get(PREVIEW_COOKIE)?.value,
      process.env.TP_PREVIEW_ACCESS_CODE,
    )
  ) {
    const target = new URL("/preview", request.url);
    const next =
      pendingPath(request.nextUrl.pathname) ??
      pendingPath(request.nextUrl.searchParams.get("next"));
    if (next) target.searchParams.set("next", next);
    return NextResponse.redirect(target, 303);
  }
  return NextResponse.next();
}
export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
