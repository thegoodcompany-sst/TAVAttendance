import {
  test,
  expect,
  ownerQuery,
  identities,
  s,
  blockExternal,
  login,
  openLesson,
} from "./helpers";
test.beforeEach(async ({ page }) => blockExternal(page));
test("simulation records only dry-run delivery; snooze defers ten minutes without submission", async ({
  page,
  lessonId,
}) => {
  await login(page);
  await openLesson(page, lessonId);
  await page.getByRole("button", { name: s.ping }).click();
  await expect(page.getByTestId("notification")).toBeVisible();
  const before = Date.now();
  await page
    .getByTestId("notification")
    .getByRole("button", { name: s.remind })
    .click();
  await expect(page.getByRole("status")).toHaveText(s.snoozed);
  const row = (
    await ownerQuery(
      "SELECT snoozed_until,snooze_count,(SELECT count(*) FROM lesson_submissions WHERE lesson_id=$1) AS submissions FROM lessons WHERE id=$1",
      [lessonId],
    )
  ).rows[0];
  expect(new Date(row.snoozed_until).getTime() - before).toBeGreaterThan(
    599000,
  );
  expect(new Date(row.snoozed_until).getTime() - before).toBeLessThan(620000);
  expect(row.submissions).toBe("0");
  const logs = await ownerQuery(
    "SELECT d.transport FROM notification_deliveries d JOIN notification_outbox o ON o.id=d.outbox_id JOIN notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=$1 AND p.kind='simulation'",
    [lessonId],
  );
  expect(logs.rows).toEqual([{ transport: "dry_run" }]);
});
test("no-device teacher can review; network save failure is shown and draft survives conflict", async ({
  page,
  lessonId,
}) => {
  await ownerQuery("UPDATE teacher_devices SET revoked_at=now()");
  await login(page);
  await openLesson(page, lessonId);
  await page.getByLabel(s.notes, { exact: true }).fill("Keep this draft");
  await page.route("**/t/lesson/*", (route) =>
    route.request().method() === "POST"
      ? route.abort("failed")
      : route.continue(),
  );
  await page.getByRole("button", { name: s.saveNotes }).click();
  await expect(page.getByRole("status")).toHaveText(s.error);
  await expect(page.getByLabel(s.notes, { exact: true })).toHaveValue(
    "Keep this draft",
  );
  await page.unroute("**/t/lesson/*");
  await ownerQuery(
    "UPDATE lessons SET register_revision=register_revision+1 WHERE id=$1",
    [lessonId],
  );
  await page.getByTestId("student").last().locator("button.status").click();
  await expect(page.getByRole("status")).toHaveText(s.stale);
  await expect(page.getByLabel(s.notes, { exact: true })).toHaveValue(
    "Keep this draft",
  );
  await page.getByTestId("student").last().locator("button.status").click();
  await expect(
    page.getByTestId("student").last().locator("button.status"),
  ).toHaveText(s.present);
});
test("admin reassignment changes route access and cancellation suppresses queue", async ({
  page,
  lessonId,
}) => {
  await login(page, 0);
  await openLesson(page, lessonId);
  await page.getByText(s.adminTools, { exact: true }).click();
  await page
    .getByLabel(s.substitute, { exact: true })
    .selectOption(identities[2].id);
  await page.getByRole("button", { name: s.assign, exact: true }).click();
  await expect(page.getByRole("status")).toHaveText(s.updated);
  await login(page, 4);
  await page.goto("/t/lesson/" + lessonId);
  await expect(
    page.getByRole("heading", { name: s.unavailable }),
  ).toBeVisible();
  await login(page, 2);
  await openLesson(page, lessonId);
  await login(page, 0);
  await openLesson(page, lessonId);
  await page.getByText(s.adminTools, { exact: true }).click();
  await page.getByRole("button", { name: s.cancelLesson, exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: s.confirm, exact: true })
    .click();
  await expect(page.getByText(s.cancelled, { exact: true })).toBeVisible();
  expect(
    (
      await ownerQuery(
        "SELECT count(*) FROM notification_plans WHERE lesson_id=$1 AND status='pending'",
        [lessonId],
      )
    ).rows[0].count,
  ).toBe("0");
});
test("query failure reaches explicit error boundary", async ({
  page,
  lessonId,
}) => {
  await login(page);
  await ownerQuery(
    "UPDATE feature_flags SET enabled=false WHERE key='teacher_prompts'",
  );
  await page.goto("/t/lesson/" + lessonId);
  await expect(page.getByRole("heading", { name: s.error })).toBeVisible();
  await expect(page.getByRole("button", { name: s.retry })).toBeVisible();
});
test("admin reschedules an untouched future lesson without changing its identity", async ({
  page,
  lessonId,
}) => {
  expect(lessonId).toBeTruthy();
  const original = (
    await ownerQuery(
      "SELECT id,scheduled_start_at,scheduled_end_at FROM lessons WHERE scheduled_start_at>now()+interval '1 day' AND cancelled_at IS NULL ORDER BY scheduled_start_at LIMIT 1",
    )
  ).rows[0];
  const start = new Date(original.scheduled_start_at).getTime() + 15 * 60000,
    end = new Date(original.scheduled_end_at).getTime() + 15 * 60000;
  const input = (value: number) =>
    new Date(value + 8 * 3600000).toISOString().slice(0, 16);
  await login(page, 0);
  await openLesson(page, original.id);
  await page.getByText(s.adminTools, { exact: true }).click();
  await page.getByLabel(s.start, { exact: true }).fill(input(start));
  await page.getByLabel(s.end, { exact: true }).fill(input(end));
  await page.getByRole("button", { name: s.editSchedule }).click();
  await expect(page.getByRole("status")).toHaveText(s.updated);
  await expect(page).toHaveURL("/t/lesson/" + original.id);
  const changed = (
    await ownerQuery(
      "SELECT scheduled_start_at,schedule_overridden FROM lessons WHERE id=$1",
      [original.id],
    )
  ).rows[0];
  expect(new Date(changed.scheduled_start_at).getTime()).toBe(start);
  expect(changed.schedule_overridden).toBe(true);
});
