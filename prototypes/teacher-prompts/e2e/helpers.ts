import { test as base, expect, type Page } from "@playwright/test";
import { resetDatabase, ownerQuery } from "../scripts/database";
import { identities } from "../lib/identity";
import { previewCookie, PREVIEW_COOKIE } from "../lib/preview";
import { s } from "../lib/strings";
export const test = base.extend<{ lessonId: string; previewAccess: void }>({
  previewAccess: [
    async ({ context }, provide) => {
      await context.addCookies([
        {
          name: PREVIEW_COOKIE,
          value: previewCookie("e2e-local-code"),
          domain: "127.0.0.1",
          path: "/",
          httpOnly: true,
          sameSite: "Lax",
        },
      ]);
      await provide();
    },
    { auto: true },
  ],
  lessonId: async ({}, provide) => {
    await provide(await resetDatabase());
  },
});
export { expect, ownerQuery, identities, s };
export async function blockExternal(page: Page) {
  await page.route("**/*", (route) => {
    const url = new URL(route.request().url());
    return ["127.0.0.1", "localhost"].includes(url.hostname)
      ? route.continue()
      : route.abort("blockedbyclient");
  });
}
export async function login(page: Page, index = 4) {
  await page.goto("/demo");
  await page.getByLabel(s.selectIdentity).selectOption(identities[index].id);
  await page.getByRole("button", { name: s.continue, exact: true }).click();
  await expect(page).toHaveURL(/\/$/);
}
export async function openLesson(page: Page, lessonId: string) {
  await page.goto("/t/lesson/" + lessonId);
  await expect(
    page.getByRole("heading", { name: s.attendance, exact: true }),
  ).toBeVisible();
}
export async function markAll(page: Page) {
  await page
    .getByRole("button", { name: s.markPresentOnly, exact: true })
    .click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: s.confirm, exact: true })
    .click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
}
