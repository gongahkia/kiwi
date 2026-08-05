import { defineConfig } from "@playwright/test";

export default defineConfig({
  expect: {
    timeout: 5000
  },
  fullyParallel: true,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  retries: process.env.CI ? 1 : 0,
  testDir: "./e2e",
  timeout: 30000,
  use: {
    baseURL: "http://127.0.0.1:3100",
    trace: "retain-on-failure"
  },
  webServer: {
    command: "pnpm --filter @wat/web exec next dev -H 127.0.0.1 -p 3100",
    env: {
      WAT_RATE_LIMIT_IP: "100000",
      WAT_RATE_LIMIT_TEAM: "100000",
      WAT_RATE_LIMIT_USER: "100000"
    },
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
    url: "http://127.0.0.1:3100"
  },
  workers: process.env.CI ? 2 : undefined
});
