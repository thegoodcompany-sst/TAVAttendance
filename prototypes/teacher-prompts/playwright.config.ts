import { defineConfig } from "@playwright/test";
import { assignedDatabase } from "./lib/config";
const assigned = assignedDatabase(process.env.TP_DB);
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
    command: "bun --no-env-file run build && bun --no-env-file run start",
    url: "http://127.0.0.1:3100/demo",
    reuseExistingServer: false,
    timeout: 120000,
    env: {
      TP_DATABASE_URL: `postgresql://postgres@localhost:55432/${assigned}`,
      TP_DB: assigned,
      DATABASE_URL: "",
      TP_ALLOW_REMOTE_PREVIEW_DB: "",
      TP_PREVIEW_ACCESS_CODE: "e2e-local-code-at-least-24-characters",
      TEACHER_PROMPTS_DEMO: "1",
      NEXT_TELEMETRY_DISABLED: "1",
    },
  },
});
