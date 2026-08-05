import { defineConfig } from "@playwright/test";

export default defineConfig({
  expect: {
    timeout: 5000
  },
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  testDir: "./extensions/browser/e2e",
  timeout: 30000,
  use: {
    trace: "retain-on-failure"
  },
  workers: 1
});
