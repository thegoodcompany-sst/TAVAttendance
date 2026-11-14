import "server-only";
import { cookies, headers } from "next/headers";
import { demoIdentity, IDENTITY_COOKIE } from "./identity";
export async function currentIdentity() {
  return demoIdentity((await cookies()).get(IDENTITY_COOKIE)?.value);
}
export async function requireIdentity() {
  const identity = await currentIdentity();
  if (!identity) throw new Error("TP_NOT_AVAILABLE");
  return identity;
}
export async function sameOrigin() {
  const h = await headers();
  const origin = h.get("origin");
  const host = h.get("host");
  if (!origin || new URL(origin).host !== host)
    throw new Error("TP_NOT_AVAILABLE");
}
export async function secureCookie() {
  return (await headers()).get("x-forwarded-proto") === "https";
}
