import { s } from "./strings";
export const identities = [
  { id: "10000000-0000-4000-8000-000000000001", label: s.demoAdmin },
  { id: "10000000-0000-4000-8000-000000000011", label: s.demoA },
  { id: "10000000-0000-4000-8000-000000000012", label: s.demoB },
  { id: "10000000-0000-4000-8000-000000000013", label: s.demoC },
  { id: "10000000-0000-4000-8000-000000000014", label: s.demoD },
  { id: "10000000-0000-4000-8000-000000000099", label: s.demoParent },
] as const;
export const IDENTITY_COOKIE = "tp_identity";
export const PENDING_COOKIE = "tp_pending";
export const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function demoIdentity(value: unknown) {
  return identities.find((i) => i.id === value) ?? null;
}
export function pendingPath(value: unknown): string | null {
  return typeof value === "string" &&
    /^\/t\/lesson\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      value,
    )
    ? value
    : null;
}
export function nextStatus(
  status: import("./types").Status,
): import("./types").Status {
  return status === null
    ? "present"
    : status === "present"
      ? "late"
      : status === "late"
        ? "absent"
        : "present";
}
