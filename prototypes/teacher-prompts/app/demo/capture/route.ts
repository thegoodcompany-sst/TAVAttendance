import { NextRequest, NextResponse } from "next/server";
import { pendingPath, PENDING_COOKIE } from "@/lib/identity";
export async function GET(request: NextRequest) {
  const next = pendingPath(request.nextUrl.searchParams.get("next"));
  const target = new URL("/demo", request.url);
  if (next) target.searchParams.set("next", next);
  const response = new NextResponse(null, {
    status: 303,
    headers: { Location: target.pathname + target.search },
  });
  if (next)
    response.cookies.set(PENDING_COOKIE, next, {
      httpOnly: true,
      sameSite: "lax",
      secure: request.nextUrl.protocol === "https:",
      path: "/",
      maxAge: 86400,
    });
  return response;
}
