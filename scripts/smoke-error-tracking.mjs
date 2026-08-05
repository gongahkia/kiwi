#!/usr/bin/env node
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const packageJson = require("../package.json");

export function smokeErrorTrackingConfig(argv = process.argv.slice(2), env = process.env) {
  const args = [...argv];
  if (args[0] === "--") args.shift();

  let url = env.WAT_DEPLOY_URL ?? env.NEXT_PUBLIC_SITE_URL;
  let token = env.WAT_ERROR_TEST_TOKEN ?? env.ERROR_TEST_TOKEN;
  let timeoutMs = Number(env.WAT_SMOKE_TIMEOUT_MS ?? 5000);

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--url") url = args[++index];
    if (arg === "--token") token = args[++index];
    if (arg === "--timeout-ms") timeoutMs = Number(args[++index]);
  }

  if (!url) throw new Error("missing --url or WAT_DEPLOY_URL/NEXT_PUBLIC_SITE_URL");
  if (!token) throw new Error("missing --token or WAT_ERROR_TEST_TOKEN/ERROR_TEST_TOKEN");
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) throw new Error("timeout must be positive");

  return { timeoutMs, token, url: url.replace(/\/+$/, "") };
}

export async function smokeErrorTracking({ fetchImpl = fetch, timeoutMs = 5000, token, url }) {
  const response = await fetchImpl(`${url}/api/error-test`, {
    headers: { "x-wat-error-test-token": token },
    signal: AbortSignal.timeout(timeoutMs)
  });
  const body = await response.text().catch(() => "");

  if (response.status < 500) {
    throw new Error(
      `error smoke returned ${response.status}; expected a server error from /api/error-test`
    );
  }

  return { body, status: response.status, url };
}

async function main() {
  const config = smokeErrorTrackingConfig();
  const result = await smokeErrorTracking(config);
  console.log(`error tracking smoke triggered ${result.status}: ${result.url}/api/error-test`);
  console.log(
    `verify the matching event in ERROR_TRACKING_WEBHOOK_URL dashboard for ${packageJson.name}`
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
