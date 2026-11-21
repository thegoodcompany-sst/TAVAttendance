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
test("signed-out lesson link survives wrong account and resumes on authorized identity", async ({
  page,
  lessonId,
  context,
}) => {
  await page.goto("/t/lesson/" + lessonId);
  await expect(page).toHaveURL(/\/demo\?next=/);
  expect(
    (await context.cookies()).find((c) => c.name === "tp_pending")?.httpOnly,
  ).toBe(true);
  await page.getByLabel(s.selectIdentity).selectOption(identities[2].id);
  await page.getByRole("button", { name: s.continue, exact: true }).click();
  await expect(
    page.getByRole("heading", { name: s.unavailable }),
  ).toBeVisible();
  await expect(page.getByText("Demo Student 11")).toHaveCount(0);
  expect((await context.cookies()).some((c) => c.name === "tp_pending")).toBe(
    true,
  );
  await page.getByLabel(s.selectIdentity).selectOption(identities[4].id);
  await page.getByRole("button", { name: s.continue, exact: true }).click();
  await expect(page).toHaveURL("/t/lesson/" + lessonId);
  await expect(
    page.getByRole("heading", { name: s.attendance, exact: true }),
  ).toBeVisible();
  expect((await context.cookies()).some((c) => c.name === "tp_pending")).toBe(
    false,
  );
});
test("account switch clears draft and wrong teacher sees a neutral denied route", async ({
  page,
  lessonId,
}) => {
  await login(page);
  await openLesson(page, lessonId);
  await page.getByLabel(s.notes, { exact: true }).fill("Unsaved private draft");
  await login(page, 2);
  await page.goto("/t/lesson/" + lessonId);
  await expect(
    page.getByRole("heading", { name: s.unavailable }),
  ).toBeVisible();
  await expect(page.getByText("Demo Student 11")).toHaveCount(0);
  await expect(page.getByText("Unsaved private draft")).toHaveCount(0);
  await page.goto("/admin");
  await expect(
    page.getByRole("heading", { name: s.unavailable }),
  ).toBeVisible();
});
test("forged server action student/lesson ids and changed identity are rejected", async ({
  page,
  lessonId,
  context,
}) => {
  await login(page);
  await openLesson(page, lessonId);
  await page.route("**/t/lesson/*", async (route) => {
    if (route.request().method() !== "POST") return route.continue();
    const body = route.request().postData()!;
    return route.continue({
      postData: body.replace(
        /20000000-0000-4000-8000-0000000000\d\d/g,
        "20000000-0000-4000-8000-999999999999",
      ),
    });
  });
  await page.getByTestId("student").last().locator("button.status").click();
  await expect(page.getByRole("status")).toBeVisible();
  expect(
    (
      await ownerQuery(
        "SELECT count(*) FROM attendance_records WHERE student_id=$1",
        ["20000000-0000-4000-8000-999999999999"],
      )
    ).rows[0].count,
  ).toBe("0");
  await page.unroute("**/t/lesson/*");
  await context.addCookies([
    {
      name: "tp_identity",
      value: identities[2].id,
      url: "http://127.0.0.1:3100",
    },
  ]);
  await page.getByRole("button", { name: s.ping }).click();
  await expect(page.getByRole("status")).toHaveText(s.unavailable);
  await expect(page.getByTestId("notification")).toHaveCount(0);
});
test("admin date filters and source exclusion hide Study Space", async ({
  page,
  lessonId,
}) => {
  await ownerQuery(
    "UPDATE lessons SET scheduled_end_at=now()-interval '1 minute' WHERE id=$1",
    [lessonId],
  );
  await login(page, 0);
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/admin");
  await expect(page.locator(`a[href="/t/lesson/${lessonId}"]`)).toBeVisible();
  await ownerQuery(
    "UPDATE classes SET is_study_space=true WHERE id='30000000-0000-4000-8000-000000000002'",
  );
  await page.reload();
  await expect(page.locator(`a[href="/t/lesson/${lessonId}"]`)).toHaveCount(0);
  await page.goto("/");
  await expect(page.locator(`a[href="/t/lesson/${lessonId}"]`)).toHaveCount(0);
  await page.goto("/t/lesson/" + lessonId);
  await expect(
    page.getByRole("heading", { name: s.unavailable }),
  ).toBeVisible();
  await page.goto("/admin");
  await page.getByLabel(s.from).fill("2030-01-01");
  await page.getByLabel(s.until).fill("2030-01-02");
  await page.getByRole("button", { name: s.filter }).click();
  await expect(page.getByText(s.noMissing)).toBeVisible();
});
test("sign-out removes pending route and external next cannot redirect", async ({
  page,
  lessonId,
  context,
}) => {
  await login(page);
  await page.goto("/demo?next=" + encodeURIComponent("/t/lesson/" + lessonId));
  await page.getByRole("button", { name: s.signOut, exact: true }).click();
  await expect(page).toHaveURL("/demo");
  expect(
    (await context.cookies()).some((c) =>
      ["tp_identity", "tp_pending"].includes(c.name),
    ),
  ).toBe(false);
  await page.goto("/demo?next=https%3A%2F%2Fevil.invalid");
  await page.getByRole("button", { name: s.continue, exact: true }).click();
  await expect(page).toHaveURL("/");
});
