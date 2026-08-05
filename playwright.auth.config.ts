import { defineConfig } from "@playwright/test";

const baseURL = "http://127.0.0.1:3101";
const databaseUrl = "postgres://wat:wat@127.0.0.1:55433/wat_auth_e2e";

export default defineConfig({
  expect: {
    timeout: 10000
  },
  reporter: "list",
  testDir: "./e2e",
  timeout: 60000,
  use: {
    baseURL,
    trace: "retain-on-failure"
  },
  webServer: {
    command: "pnpm --filter @wat/web exec next dev -H 127.0.0.1 -p 3101",
    env: {
      AUTH_SECRET: "local-e2e-auth-secret",
      DATABASE_URL: databaseUrl,
      EMAIL_FROM: "wat@localhost",
      EMAIL_SERVER: "smtp://127.0.0.1:1025",
      NEXTAUTH_SECRET: "local-e2e-auth-secret",
      NEXTAUTH_URL: baseURL,
      NEXT_PUBLIC_SITE_URL: baseURL
    },
    reuseExistingServer: false,
    timeout: 120000,
    url: baseURL
  },
  workers: 1
});
