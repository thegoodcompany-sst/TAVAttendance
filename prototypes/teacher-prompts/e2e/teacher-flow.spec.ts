import {
  test,
  expect,
  ownerQuery,
  s,
  blockExternal,
  login,
  openLesson,
  markAll,
} from "./helpers";
test.beforeEach(async ({ page }) => blockExternal(page));
test("teacher completes notification → attendance → optional notes → submission", async ({
  page,
  lessonId,
}) => {
  await login(page);
  await expect(page.getByRole("heading", { name: s.today })).toBeVisible();
  await page.getByRole("button", { name: s.ping }).click();
  const banner = page.getByTestId("notification");
  await expect(banner).toBeVisible();
  await expect(banner).not.toContainText("Demo Student");
  await banner
    .getByRole("link", { name: s.takeAttendance, exact: true })
    .click();
  await expect(banner).toHaveCount(0);
  await expect(page).toHaveURL("/t/lesson/" + lessonId);
  const student = page.getByTestId("student").last();
  const status = student.locator("button.status");
  await status.click();
  await expect(status).toHaveText(s.present);
  await status.click();
  await expect(status).toHaveText(s.late);
  await status.click();
  await expect(status).toHaveText(s.absent);
  await student.getByLabel(s.informed).click();
  await expect(student.getByLabel(s.informed)).toBeChecked();
  await student
    .getByRole("button", { name: new RegExp("^" + s.clear) })
    .click();
  await expect(status).toHaveText(s.notMarked);
  await expect(
    page.getByRole("button", { name: s.submit, exact: true }),
  ).toBeDisabled();
  await markAll(page);
  await expect(status).toHaveText(s.present);
  await page
    .getByLabel(s.notes, { exact: true })
    .fill("Reviewed fractions. Practise equivalent fractions.");
  await page.getByRole("button", { name: s.saveNotes }).click();
  await expect(page.getByRole("status")).toHaveText(s.savedNotes);
  await page.getByRole("button", { name: s.submit, exact: true }).click();
  await expect(page.getByTestId("done")).toBeVisible();
  await expect(page.getByLabel(s.notes, { exact: true })).toBeDisabled();
  await expect(page.getByRole("button", { name: s.ping })).toHaveCount(0);
  await page.getByTestId("done").getByRole("link", { name: s.back }).click();
  await expect(page.locator(`a[href="/t/lesson/${lessonId}"]`)).toContainText(
    s.states.submitted,
  );
  const counts = await ownerQuery<{ count: string }>(
    "SELECT count(*) FROM notification_plans WHERE lesson_id=$1 AND status='pending'",
    [lessonId],
  );
  expect(counts.rows[0].count).toBe("0");
  await login(page, 0);
  await page.goto("/admin");
  await expect(page.locator(`a[href="/t/lesson/${lessonId}"]`)).toHaveCount(0);
});
test("mark all preserves late/absent and blank feedback is allowed", async ({
  page,
  lessonId,
}) => {
  await login(page);
  await openLesson(page, lessonId);
  const absent = await page.locator("button.status.absent").count();
  const late = await page.locator("button.status.late").count();
  expect(absent).toBeGreaterThan(0);
  await markAll(page);
  await expect(page.locator("button.status.absent")).toHaveCount(absent);
  await expect(page.locator("button.status.late")).toHaveCount(late);
  await page.getByLabel(s.notes, { exact: true }).fill("");
  if (await page.getByRole("button", { name: s.saveNotes }).isEnabled()) {
    await page.getByRole("button", { name: s.saveNotes }).click();
    await expect(page.getByRole("status")).toHaveText(s.savedNotes);
  }
  await page.getByRole("button", { name: s.submit, exact: true }).click();
  await expect(page.getByTestId("done")).toBeVisible();
});
test("system appearance and manual toggle work without horizontal overflow", async ({
  page,
  lessonId,
}) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await login(page);
  await openLesson(page, lessonId);
  await expect(page.getByRole("button", { name: s.theme })).toHaveText(s.light);
  expect(
    await page.evaluate(() => getComputedStyle(document.body).backgroundColor),
  ).toBe("rgb(16, 25, 35)");
  await page.getByRole("button", { name: s.theme }).click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= 390),
  ).toBe(true);
});
