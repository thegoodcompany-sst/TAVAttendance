import {
  test,
  expect,
  login,
  openLesson,
  ownerQuery,
  s,
  blockExternal,
} from "./helpers";
test.beforeEach(async ({ page }) => blockExternal(page));
test("all-present completion takes at most three taps from notification", async ({
  page,
  lessonId,
}) => {
  await ownerQuery("DELETE FROM public.attendance_records WHERE lesson_id=$1", [
    lessonId,
  ]);
  await ownerQuery("DELETE FROM public.lesson_feedback WHERE lesson_id=$1", [
    lessonId,
  ]);
  await ownerQuery(
    "UPDATE public.lessons SET register_revision=register_revision+1 WHERE id=$1",
    [lessonId],
  );
  await login(page);
  await page
    .locator("section")
    .filter({ has: page.locator(`a[href="/t/lesson/${lessonId}"]`) })
    .getByRole("button", { name: s.ping })
    .click();
  let taps = 0;
  await page
    .getByTestId("notification")
    .getByRole("link", { name: s.takeAttendance, exact: true })
    .click();
  taps++;
  await page.getByRole("button", { name: s.allPresent, exact: true }).click();
  taps++;
  await expect(page.getByRole("dialog")).toContainText(s.presentSummary(10, 0));
  await page
    .getByRole("dialog")
    .getByRole("button", { name: s.confirmAndSubmit, exact: true })
    .click();
  taps++;
  await expect(page.getByTestId("done")).toBeVisible();
  expect(taps).toBeLessThanOrEqual(3);
  const result = await ownerQuery(
    "SELECT count(*)::int AS n FROM public.notification_plans WHERE lesson_id=$1 AND status='pending'",
    [lessonId],
  );
  expect(result.rows[0].n).toBe(0);
});
test("atomic completion preserves existing late and absent marks", async ({
  page,
  lessonId,
}) => {
  const before = await ownerQuery(
    "SELECT student_id,status,absence_informed,marked_at FROM public.attendance_records WHERE lesson_id=$1 AND status IN ('late','absent') ORDER BY student_id",
    [lessonId],
  );
  await login(page);
  await openLesson(page, lessonId);
  await page.getByRole("button", { name: s.allPresent, exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText(
    s.presentSummary(10 - before.rowCount!, before.rowCount!),
  );
  await page
    .getByRole("button", { name: s.confirmAndSubmit, exact: true })
    .click();
  await expect(page.getByTestId("done")).toBeVisible();
  const after = await ownerQuery(
    "SELECT student_id,status,absence_informed,marked_at FROM public.attendance_records WHERE lesson_id=$1 AND status IN ('late','absent') ORDER BY student_id",
    [lessonId],
  );
  expect(after.rows).toEqual(before.rows);
});
test("keyboard confirmation traps focus, Escape cancels and restores opener", async ({
  page,
  lessonId,
}) => {
  await login(page);
  await openLesson(page, lessonId);
  for (const label of [s.allPresent, s.markPresentOnly]) {
    const opener = page.getByRole("button", { name: label, exact: true });
    await opener.focus();
    await page.keyboard.press("Enter");
    const dialog = page.getByRole("dialog");
    await expect(dialog).toHaveAttribute("aria-labelledby", /.+/);
    const confirm = dialog.getByRole("button", {
      name: label === s.allPresent ? s.confirmAndSubmit : s.confirm,
      exact: true,
    });
    await expect(confirm).toBeFocused();
    await page.keyboard.press("Shift+Tab");
    await expect(
      dialog.getByRole("button", { name: s.cancel, exact: true }),
    ).toBeFocused();
    await page.keyboard.press("Tab");
    await expect(confirm).toBeFocused();
    await page.keyboard.press("Escape");
    await expect(dialog).toHaveCount(0);
    await expect(opener).toBeFocused();
  }
});
test("admin cancel dialog restores keyboard focus", async ({
  page,
  lessonId,
}) => {
  await login(page, 0);
  await openLesson(page, lessonId);
  await page.getByText(s.adminTools, { exact: true }).click();
  const opener = page.getByRole("button", {
    name: s.cancelLesson,
    exact: true,
  });
  await opener.focus();
  await page.keyboard.press("Enter");
  await expect(
    page
      .getByRole("dialog")
      .getByRole("button", { name: s.confirm, exact: true }),
  ).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(opener).toBeFocused();
});

test("stale all-present confirmation stays unsubmitted and preserves unmarked rows", async ({
  page,
  lessonId,
}) => {
  await login(page);
  await openLesson(page, lessonId);
  await page.getByLabel(s.notes, { exact: true }).fill("Unsaved lesson note");
  await expect(
    page.getByRole("button", { name: s.allPresent, exact: true }),
  ).toBeDisabled();
  await page.getByRole("button", { name: s.saveNotes, exact: true }).click();
  await expect(page.getByRole("status")).toHaveText(s.savedNotes);
  await page.getByRole("button", { name: s.allPresent, exact: true }).click();
  const before = await ownerQuery(
    "SELECT count(*)::int AS n FROM attendance_records WHERE lesson_id=$1",
    [lessonId],
  );
  await ownerQuery(
    "UPDATE lessons SET register_revision=register_revision+1 WHERE id=$1",
    [lessonId],
  );
  await page
    .getByRole("button", { name: s.confirmAndSubmit, exact: true })
    .click();
  await expect(page.getByRole("dialog").getByRole("status")).toHaveText(
    s.stale,
  );
  const after = await ownerQuery(
    "SELECT count(*)::int AS n FROM attendance_records WHERE lesson_id=$1",
    [lessonId],
  );
  expect(after.rows).toEqual(before.rows);
  expect(
    (
      await ownerQuery(
        "SELECT count(*)::int AS n FROM lesson_submissions WHERE lesson_id=$1",
        [lessonId],
      )
    ).rows[0].n,
  ).toBe(0);
  await page.keyboard.press("Escape");
  await expect(
    page.getByRole("button", { name: s.allPresent, exact: true }),
  ).toBeFocused();
});
