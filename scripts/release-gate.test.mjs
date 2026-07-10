import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  requiredDocTokens,
  validateDocs,
  validatePackageScripts,
  validateReleaseGate,
  validateWorkflow
} from "./release-gate.mjs";

function readDocs() {
  return Object.fromEntries(
    Object.keys(requiredDocTokens).map((path) => [path, readFileSync(path, "utf8")])
  );
}

describe("release gate coverage", () => {
  it("covers local release acceptance commands and manual evidence docs", () => {
    const result = validateReleaseGate({
      docs: readDocs(),
      packageJsonText: readFileSync("package.json", "utf8"),
      workflowText: readFileSync(".github/workflows/ci.yml", "utf8")
    });

    assert.equal(result.ok, true);
    assert.deepEqual(result.missingPackageScripts, []);
    assert.deepEqual(result.missingWorkflowCommands, []);
    assert.deepEqual(result.missingDocTokens, []);
  });

  it("fails when required scripts, workflow commands, or doc tokens drift", () => {
    assert.deepEqual(
      validatePackageScripts(JSON.stringify({ scripts: { "test:helm": "node nope.mjs" } })),
      [
        "alerts:check: node scripts/validate-alert-rules.mjs",
        "backup:verify: node scripts/verify-backup-archive.mjs",
        "dashboard:check: node scripts/validate-monitoring-dashboard.mjs",
        "infra:fly:check: node scripts/validate-fly-config.mjs",
        "launch:metrics:check: node scripts/validate-launch-metrics.mjs",
        "load:search: k6 run scripts/k6-search.js",
        "smoke:deployment: node scripts/smoke-deployment.mjs",
        "smoke:error-tracking: node scripts/smoke-error-tracking.mjs",
        "smoke:platforms: node scripts/smoke-platforms.mjs all",
        "test:e2e:auth: sh scripts/e2e-auth-mailpit.sh",
        "test:e2e:extension: pnpm --filter @wat/ext build && playwright test -c playwright.extension.config.ts",
        "test:e2e:web: playwright test e2e/web-search.spec.ts",
        "test:error-tracking-smoke: node --test scripts/smoke-error-tracking.test.mjs",
        "test:backup-verify: node --test scripts/verify-backup-archive.test.mjs",
        "test:dashboard: node --test scripts/validate-monitoring-dashboard.test.mjs",
        "test:fly-config: node --test scripts/validate-fly-config.test.mjs",
        "test:launch-metrics: node --test scripts/validate-launch-metrics.test.mjs",
        "test:helm: node --test scripts/helm-chart.test.mjs"
      ]
    );
    assert.deepEqual(validateWorkflow("pnpm test\n"), [
      "pnpm alerts:check",
      "pnpm build:all",
      "pnpm dashboard:check",
      "pnpm db:migrate",
      "pnpm db:seed:public",
      "pnpm infra:fly:check",
      "pnpm lint",
      "pnpm release:check",
      "pnpm smoke:local-demo",
      "pnpm test:backup-verify",
      "pnpm test:dashboard",
      "pnpm test:error-tracking-smoke",
      "pnpm test:e2e:extension",
      "pnpm test:e2e:web",
      "pnpm test:fly-config",
      "pnpm test:launch-metrics",
      "pnpm test:helm",
      "pnpm typecheck"
    ]);
    assert.deepEqual(validateDocs({ "docs/performance.md": "pnpm load:search" }), [
      "docs/browser-extension-release.md: pnpm --filter @wat/ext build:stores",
      "docs/launch-metrics.md: github_stars",
      "docs/launch-metrics.md: hosted_searches",
      "docs/launch-metrics.md: extension_installs",
      "docs/launch-metrics.md: slack_installs",
      "docs/launch-metrics.md: mcp_installs",
      "docs/launch-metrics.md: docs_visits",
      "docs/launch-metrics.md: pnpm launch:metrics:check",
      "docs/performance.md: WAT_K6_P95_MS=150",
      "docs/performance.md: WAT_K6_P95_MS=300",
      "infra/fly/README.md: apps/slack/Dockerfile",
      "infra/fly/README.md: slack_app_name",
      "infra/fly/README.md: slack_image",
      "infra/fly/README.md: slack_signing_secret",
      'infra/fly/README.md: curl -f "$(terraform output -raw slack_url)/healthz"',
      "docs/production-readiness.md: pnpm dashboard:check",
      "docs/production-readiness.md: infra/monitoring/grafana-dashboard.json",
      "docs/production-readiness.md: ERROR_TRACKING_WEBHOOK_URL",
      "docs/production-readiness.md: ERROR_TEST_TOKEN",
      "docs/production-readiness.md: pnpm backup:verify",
      "docs/production-readiness.md: pnpm smoke:error-tracking",
      "docs/production-readiness.md: pnpm smoke:deployment",
      "docs/production-readiness.md: pnpm smoke:platforms",
      "docs/production-readiness.md: browser extension",
      "docs/production-readiness.md: MCP",
      "docs/self-host.md: Clean install acceptance",
      "docs/self-host.md: docker compose up --build",
      "docs/self-host.md: pnpm smoke:deployment -- --url http://localhost:3000"
    ]);
  });
});
