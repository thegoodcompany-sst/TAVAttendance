import { test, expect, s, blockExternal } from "./helpers";
test.beforeEach(async ({ page, context }) => {
  await blockExternal(page);
  await context.clearCookies();
});
test("shared code gates identity selection and resumes the lesson after admission", async ({
  page,
  lessonId,
  context,
}) => {
  await page.goto("/t/lesson/" + lessonId);
  await expect(page).toHaveURL(/\/preview\?next=/);
  await expect(page.getByLabel(s.selectIdentity)).toHaveCount(0);
  await page.getByLabel(s.accessCode, { exact: true }).fill("incorrect");
  await page.getByRole("button", { name: s.continue, exact: true }).click();
  await expect(page.getByRole("status")).toHaveText(s.invalidAccessCode);
  await expect(page.getByLabel(s.selectIdentity)).toHaveCount(0);
  await page.getByLabel(s.accessCode, { exact: true }).fill("e2e-local-code");
  await page.getByRole("button", { name: s.continue, exact: true }).click();
  await expect(page.getByLabel(s.selectIdentity)).toBeVisible();
  const cookie = (await context.cookies()).find((c) => c.name === "tp-preview");
  expect(cookie?.httpOnly).toBe(true);
  expect(cookie?.sameSite).toBe("Lax");
  expect(cookie?.value).not.toContain("e2e-local-code");
  await page.getByRole("button", { name: s.continue, exact: true }).click();
  await expect(page).toHaveURL("/t/lesson/" + lessonId);
  await expect(
    page.getByRole("heading", { name: s.attendance, exact: true }),
  ).toBeVisible();
});
test("forged access cookie and seeded admin identity cannot bypass page gate", async ({
  page,
  context,
}) => {
  await context.addCookies([
    { name: "tp-preview", value: "yes", domain: "127.0.0.1", path: "/" },
    {
      name: "tp_identity",
      value: "10000000-0000-4000-8000-000000000001",
      domain: "127.0.0.1",
      path: "/",
    },
  ]);
  for (const path of ["/", "/admin", "/demo", "/demo/capture"]) {
    await page.goto(path);
    await expect(
      page.getByRole("heading", { name: s.previewAccess }),
    ).toBeVisible();
    await expect(page.getByLabel(s.selectIdentity)).toHaveCount(0);
  }
});
