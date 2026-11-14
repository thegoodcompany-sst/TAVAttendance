import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./e2e",
  testIgnore: "screenshots.spec.ts",
  fullyParallel: false,
  workers: 1,
  timeout: 60000,
  expect: { timeout: 10000 },
  reporter: "list",
  use: {
    baseURL: "http://127.0.0.1:3100",
    viewport: { width: 390, height: 844 },
    channel: "chrome",
    trace: "off",
    screenshot: "only-on-failure",
  },
  webServer: {
    command: "bun run build && bun run start",
    url: "http://127.0.0.1:3100/demo",
    reuseExistingServer: false,
    timeout: 120000,
    env: {
      TEACHER_PROMPTS_DATABASE_URL:
        "postgresql://postgres@localhost:55432/tp_c",
      TEACHER_PROMPTS_DB_NAME: "tp_c",
      TEACHER_PROMPTS_DEMO: "1",
      NEXT_TELEMETRY_DISABLED: "1",
    },
  },
});
