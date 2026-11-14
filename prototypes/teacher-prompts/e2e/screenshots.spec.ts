import { mkdir } from "node:fs/promises";
import {
  test,
  expect,
  s,
  login,
  openLesson,
  markAll,
  blockExternal,
  ownerQuery,
} from "./helpers";
import { resetDatabase } from "../scripts/database";
const folder = "/workspace/tav-teacher-prompts/screens";
for (const mode of ["light", "dark"] as const) {
  test(`capture every screen in ${mode}`, async ({ page }) => {
    const lessonId = await resetDatabase();
    await mkdir(folder, { recursive: true });
    await blockExternal(page);
    await page.emulateMedia({ colorScheme: mode });
    const capture = async (name: string) => {
      await page.waitForLoadState("networkidle");
      await page.evaluate(() => document.fonts.ready);
      await page.screenshot({
        path: `${folder}/${name}-${mode}.png`,
        animations: "disabled",
      });
    };
    await page.goto("/demo");
    await capture("00-identity");
    await login(page);
    await capture("01-today");
    await openLesson(page, lessonId);
    await capture("02-lesson");
    await page.getByRole("button", { name: s.ping }).click();
    await expect(page.getByTestId("notification")).toBeVisible();
    await page.evaluate(() => scrollTo(0, 0));
    await capture("03-notification");
    await page
      .getByTestId("notification")
      .getByRole("button", { name: s.remind })
      .click();
    await expect(page.getByRole("status")).toHaveText(s.snoozed);
    await capture("04-snoozed");
    await page.getByRole("button", { name: s.allPresent }).click();
    await page.getByRole("dialog").scrollIntoViewIfNeeded();
    await capture("05-attendance-confirmation");
    await page
      .getByRole("dialog")
      .getByRole("button", { name: s.cancel, exact: true })
      .click();
    const absent = page
      .getByTestId("student")
      .filter({ has: page.locator("button.status.absent") })
      .first();
    await absent.scrollIntoViewIfNeeded();
    await capture("06-attendance");
    await markAll(page);
    await page
      .getByLabel(s.notes, { exact: true })
      .fill("Reviewed fractions. Practise equivalent fractions.");
    await page.getByLabel(s.notes, { exact: true }).scrollIntoViewIfNeeded();
    await capture("07-notes");
    await page.getByRole("button", { name: s.saveNotes }).click();
    await expect(page.getByRole("status")).toHaveText(s.savedNotes);
    await page
      .getByRole("button", { name: s.submit, exact: true })
      .scrollIntoViewIfNeeded();
    await capture("08-submit");
    await page.getByRole("button", { name: s.submit, exact: true }).click();
    await expect(page.getByTestId("done")).toBeVisible();
    await page.evaluate(() => scrollTo(0, 0));
    await capture("09-done");
    await login(page, 0);
    await page.goto("/admin");
    await capture("10-admin");
    await login(page, 2);
    await page.goto("/t/lesson/" + lessonId);
    await expect(
      page.getByRole("heading", { name: s.unavailable }),
    ).toBeVisible();
    await capture("11-unavailable");
    await login(page, 0);
    const cancelled = (
      await ownerQuery(
        "SELECT id FROM lessons WHERE cancelled_at IS NOT NULL ORDER BY scheduled_start_at LIMIT 1",
      )
    ).rows[0].id;
    await page.goto("/t/lesson/" + cancelled);
    await expect(page.getByText(s.cancelled, { exact: true })).toBeVisible();
    await capture("12-cancelled");
    const future = (
      await ownerQuery(
        "SELECT id FROM lessons WHERE scheduled_start_at>now() AND cancelled_at IS NULL ORDER BY scheduled_start_at LIMIT 1",
      )
    ).rows[0].id;
    await openLesson(page, future);
    await page.getByText(s.adminTools, { exact: true }).click();
    await page
      .getByText(s.adminTools, { exact: true })
      .scrollIntoViewIfNeeded();
    await capture("13-admin-controls");
    await page.goto("/?date=2030-01-01");
    await expect(page.getByText(s.empty, { exact: true })).toBeVisible();
    await capture("14-empty");
    await ownerQuery(
      "UPDATE feature_flags SET enabled=false WHERE key='teacher_prompts'",
    );
    await page.goto("/");
    await expect(page.getByRole("heading", { name: s.error })).toBeVisible();
    await capture("15-error");
  });
}
