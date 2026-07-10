#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const requiredPackageScripts = {
  "alerts:check": "node scripts/validate-alert-rules.mjs",
  "backup:verify": "node scripts/verify-backup-archive.mjs",
  "dashboard:check": "node scripts/validate-monitoring-dashboard.mjs",
  "launch:metrics:check": "node scripts/validate-launch-metrics.mjs",
  "load:search": "k6 run scripts/k6-search.js",
  "smoke:deployment": "node scripts/smoke-deployment.mjs",
  "smoke:error-tracking": "node scripts/smoke-error-tracking.mjs",
  "smoke:platforms": "node scripts/smoke-platforms.mjs all",
  "test:e2e:auth": "sh scripts/e2e-auth-mailpit.sh",
  "test:e2e:extension":
    "pnpm --filter @wat/ext build && playwright test -c playwright.extension.config.ts",
  "test:e2e:web": "playwright test e2e/web-search.spec.ts",
  "test:error-tracking-smoke": "node --test scripts/smoke-error-tracking.test.mjs",
  "test:backup-verify": "node --test scripts/verify-backup-archive.test.mjs",
  "test:dashboard": "node --test scripts/validate-monitoring-dashboard.test.mjs",
  "test:launch-metrics": "node --test scripts/validate-launch-metrics.test.mjs",
  "test:helm": "node --test scripts/helm-chart.test.mjs"
};

export const requiredWorkflowCommands = [
  "pnpm alerts:check",
  "pnpm build:all",
  "pnpm dashboard:check",
  "pnpm db:migrate",
  "pnpm db:seed:public",
  "pnpm lint",
  "pnpm release:check",
  "pnpm smoke:local-demo",
  "pnpm test",
  "pnpm test:backup-verify",
  "pnpm test:dashboard",
  "pnpm test:error-tracking-smoke",
  "pnpm test:e2e:extension",
  "pnpm test:e2e:web",
  "pnpm test:launch-metrics",
  "pnpm test:helm",
  "pnpm typecheck"
];

export const requiredDocTokens = {
  "docs/browser-extension-release.md": ["pnpm --filter @wat/ext build:stores"],
  "docs/launch-metrics.md": [
    "github_stars",
    "hosted_searches",
    "extension_installs",
    "slack_installs",
    "mcp_installs",
    "docs_visits",
    "pnpm launch:metrics:check"
  ],
  "docs/performance.md": ["WAT_K6_P95_MS=150", "WAT_K6_P95_MS=300", "pnpm load:search"],
  "docs/production-readiness.md": [
    "pnpm dashboard:check",
    "infra/monitoring/grafana-dashboard.json",
    "ERROR_TRACKING_WEBHOOK_URL",
    "ERROR_TEST_TOKEN",
    "pnpm backup:verify",
    "pnpm smoke:error-tracking",
    "pnpm smoke:deployment",
    "pnpm smoke:platforms",
    "browser extension",
    "MCP"
  ],
  "docs/self-host.md": [
    "Clean install acceptance",
    "docker compose up --build",
    "pnpm smoke:deployment -- --url http://localhost:3000"
  ]
};

export function validatePackageScripts(packageJsonText) {
  const packageJson = JSON.parse(packageJsonText);
  const scripts = packageJson.scripts ?? {};
  return Object.entries(requiredPackageScripts)
    .filter(([name, command]) => scripts[name] !== command)
    .map(([name, command]) => `${name}: ${command}`);
}

export function validateWorkflow(workflowText) {
  return requiredWorkflowCommands.filter((command) => !workflowText.includes(command));
}

export function validateDocs(docs) {
  const missing = [];
  for (const [path, tokens] of Object.entries(requiredDocTokens)) {
    const text = docs[path] ?? "";
    for (const token of tokens) {
      if (!text.includes(token)) missing.push(`${path}: ${token}`);
    }
  }
  return missing;
}

export function validateReleaseGate(inputs) {
  const missingPackageScripts = validatePackageScripts(inputs.packageJsonText);
  const missingWorkflowCommands = validateWorkflow(inputs.workflowText);
  const missingDocTokens = validateDocs(inputs.docs);
  return {
    missingDocTokens,
    missingPackageScripts,
    missingWorkflowCommands,
    ok:
      missingPackageScripts.length === 0 &&
      missingWorkflowCommands.length === 0 &&
      missingDocTokens.length === 0
  };
}

function readDocs(paths) {
  return Object.fromEntries(paths.map((path) => [path, readFileSync(path, "utf8")]));
}

function main() {
  const result = validateReleaseGate({
    docs: readDocs(Object.keys(requiredDocTokens)),
    packageJsonText: readFileSync("package.json", "utf8"),
    workflowText: readFileSync(".github/workflows/ci.yml", "utf8")
  });
  if (!result.ok) {
    for (const item of result.missingPackageScripts)
      console.error(`missing package script: ${item}`);
    for (const item of result.missingWorkflowCommands)
      console.error(`missing workflow command: ${item}`);
    for (const item of result.missingDocTokens) console.error(`missing doc token: ${item}`);
    process.exit(1);
  }
  console.log("release gate coverage ok");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
