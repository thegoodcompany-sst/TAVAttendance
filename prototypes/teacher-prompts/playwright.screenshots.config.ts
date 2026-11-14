import { defineConfig } from "@playwright/test";
import base from "./playwright.config";
export default defineConfig({
  ...base,
  globalSetup: "./scripts/clear-screenshots.ts",
  testIgnore: [],
  testMatch: "screenshots.spec.ts",
  timeout: 180000,
});
