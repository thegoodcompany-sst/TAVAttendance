import { createHash, createHmac, timingSafeEqual } from "node:crypto";
export const PREVIEW_COOKIE = "tp-preview";
export const PREVIEW_TTL = 8 * 60 * 60;
function equal(a: string, b: string) {
  const x = createHash("sha256").update(a).digest(),
    y = createHash("sha256").update(b).digest();
  return timingSafeEqual(x, y);
}
export function accessCodeMatches(
  input: unknown,
  expected: string | undefined,
) {
  return (
    typeof input === "string" &&
    Boolean(expected && expected.trim().length >= 24) &&
    equal(input, expected!)
  );
}
export function previewCookie(code: string, now = Date.now()) {
  const expiry = String(Math.floor(now / 1000) + PREVIEW_TTL);
  return `${expiry}.${createHmac("sha256", code).update(`tp-preview:${expiry}`).digest("hex")}`;
}
export function validPreviewCookie(
  value: string | undefined,
  code: string | undefined,
  now = Date.now(),
) {
  if (
    !value ||
    !code ||
    code.trim().length < 24 ||
    !/^\d+\.[a-f0-9]{64}$/.test(value)
  )
    return false;
  const [expiry, signature] = value.split(".");
  const remaining = Number(expiry) - Math.floor(now / 1000);
  if (remaining <= 0 || remaining > PREVIEW_TTL) return false;
  return equal(
    signature,
    createHmac("sha256", code).update(`tp-preview:${expiry}`).digest("hex"),
  );
}
