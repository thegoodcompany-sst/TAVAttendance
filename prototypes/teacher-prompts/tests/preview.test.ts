import { beforeEach, afterEach, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import { proxy } from "../proxy";
import { previewCookie, PREVIEW_COOKIE } from "../lib/preview";
const jar = { get: vi.fn(), set: vi.fn(), delete: vi.fn() };
vi.mock("next/headers", () => ({
  cookies: async () => jar,
  headers: async () =>
    new Headers({
      origin: "https://preview.invalid",
      host: "preview.invalid",
      "x-forwarded-proto": "https",
    }),
}));
vi.mock("next/navigation", () => ({
  redirect: (path: string) => {
    throw new Error("REDIRECT:" + path);
  },
}));
vi.mock("../lib/db", () => ({
  ensureDemoDatabase: vi.fn().mockResolvedValue(undefined),
}));
import { requirePreviewAccess } from "../lib/access";
import { enterPreview } from "../app/actions/preview";
import { selectIdentity } from "../app/actions/identity";
import { ensureDemoDatabase } from "../lib/db";
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("TEACHER_PROMPTS_DEMO", "1");
  vi.stubEnv("TP_DB", "tp_unit");
  vi.stubEnv("TEACHER_PROMPTS_DB_NAME", "");
  vi.stubEnv("TEACHER_PROMPTS_DATABASE_URL", undefined);
  vi.stubEnv("DATABASE_URL", "postgresql://preview.invalid/tp_unit");
  vi.stubEnv("TP_ALLOW_REMOTE_PREVIEW_DB", "1");
  vi.stubEnv("TP_PREVIEW_ACCESS_CODE", "fake-code");
  jar.get.mockReturnValue(undefined);
});
afterEach(() => vi.unstubAllEnvs());
it.each([
  "/",
  "/demo",
  "/admin",
  "/t/lesson/10000000-0000-4000-8000-000000000001",
  "/demo/capture",
  "/unknown",
])("gates every page/handler before identity switching: %s", (path) => {
  const response = proxy(new NextRequest("https://preview.invalid" + path));
  expect(response.status).toBe(303);
  expect(response.headers.get("location")).toContain(
    "https://preview.invalid/preview",
  );
});
it("keeps unsigned lesson navigation through the gate and allows only its code form", () => {
  const path = "/t/lesson/10000000-0000-4000-8000-000000000001";
  const response = proxy(new NextRequest("https://preview.invalid" + path));
  expect(
    new URL(response.headers.get("location")!).searchParams.get("next"),
  ).toBe(path);
  expect(proxy(new NextRequest("https://preview.invalid/preview")).status).toBe(
    200,
  );
});
it("accepts signed cookie, rejects forged cookie and gates POST too", () => {
  expect(
    proxy(
      new NextRequest("https://preview.invalid/demo", {
        headers: { cookie: `${PREVIEW_COOKIE}=${previewCookie("fake-code")}` },
      }),
    ).status,
  ).toBe(200);
  expect(
    proxy(
      new NextRequest("https://preview.invalid/demo", {
        method: "POST",
        headers: { cookie: `${PREVIEW_COOKIE}=yes` },
      }),
    ).status,
  ).toBe(303);
});
it("rechecks access in direct identity actions before setting the admin cookie", async () => {
  const form = new FormData();
  form.set("identity", "10000000-0000-4000-8000-000000000001");
  await expect(selectIdentity(form)).rejects.toThrow("REDIRECT:/preview");
  expect(jar.set).not.toHaveBeenCalled();
});
it("rejects wrong code without issuing any cookie", async () => {
  const form = new FormData();
  form.set("code", "wrong");
  await expect(enterPreview(form)).rejects.toThrow(
    "REDIRECT:/preview?invalid=1",
  );
  expect(jar.set).not.toHaveBeenCalled();
  expect(ensureDemoDatabase).toHaveBeenCalledOnce();
});
it("correct code issues secure HttpOnly cookie and preserves only valid lesson destination", async () => {
  const form = new FormData();
  form.set("code", "fake-code");
  form.set("next", "https://elsewhere.invalid");
  await expect(enterPreview(form)).rejects.toThrow("REDIRECT:/demo");
  expect(jar.set).toHaveBeenCalledWith(
    PREVIEW_COOKIE,
    expect.any(String),
    expect.objectContaining({
      httpOnly: true,
      secure: true,
      sameSite: "lax",
      path: "/",
    }),
  );
  jar.get.mockReturnValue({ value: jar.set.mock.calls[0][1] });
  await expect(requirePreviewAccess()).resolves.toBeUndefined();
});
it("refuses preview entry if the database is not marked demo", async () => {
  vi.mocked(ensureDemoDatabase).mockRejectedValueOnce(
    new Error("TP_DEMO_REQUIRED"),
  );
  const form = new FormData();
  form.set("code", "fake-code");
  await expect(enterPreview(form)).rejects.toThrow("TP_DEMO_REQUIRED");
  expect(jar.set).not.toHaveBeenCalled();
});
it("local explicit demo requires no shared code unless configured", async () => {
  vi.stubEnv("DATABASE_URL", undefined);
  vi.stubEnv("TP_PREVIEW_ACCESS_CODE", undefined);
  expect(proxy(new NextRequest("http://127.0.0.1:3100/demo")).status).toBe(200);
  await expect(requirePreviewAccess()).resolves.toBeUndefined();
});

it("stores the valid pending lesson before redirecting from the code form", async () => {
  const next = "/t/lesson/10000000-0000-4000-8000-000000000001";
  const form = new FormData();
  form.set("code", "fake-code");
  form.set("next", next);
  await expect(enterPreview(form)).rejects.toThrow(
    "REDIRECT:/demo?next=" + encodeURIComponent(next),
  );
  expect(jar.set).toHaveBeenCalledWith(
    "tp_pending",
    next,
    expect.objectContaining({ httpOnly: true, secure: true }),
  );
});
