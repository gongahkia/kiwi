import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  requiredSecurityDocTokens,
  validateSecurityDocs,
  validateSecurityGates,
  validateSecurityScripts,
  validateSecurityWorkflow
} from "./validate-security-gates.mjs";

function readDocs() {
  return Object.fromEntries(
    Object.keys(requiredSecurityDocTokens).map((path) => [path, readFileSync(path, "utf8")])
  );
}

describe("security gate coverage", () => {
  it("covers dependency and license scan commands", () => {
    const result = validateSecurityGates({
      docs: readDocs(),
      packageJsonText: readFileSync("package.json", "utf8"),
      workflowText: readFileSync(".github/workflows/ci.yml", "utf8")
    });

    assert.equal(result.ok, true);
    assert.deepEqual(result.missingPackageScripts, []);
    assert.deepEqual(result.missingWorkflowCommands, []);
    assert.deepEqual(result.missingDocTokens, []);
  });

  it("fails when security scripts, workflow commands, or docs drift", () => {
    assert.deepEqual(validateSecurityScripts(JSON.stringify({ scripts: {} })), [
      "audit:deps: pnpm audit --audit-level high",
      "audit:deps:snyk: snyk test --all-projects --severity-threshold=high",
      "audit:licenses: pnpm licenses list --prod",
      "audit:licenses:fossa: fossa analyze && fossa test",
      "audit:licenses:scancode: scancode --license --copyright --package --json-pp artifacts/security/scancode.json .",
      "security:gates: node scripts/validate-security-gates.mjs",
      "test:security-gates: node --test scripts/validate-security-gates.test.mjs"
    ]);
    assert.deepEqual(validateSecurityWorkflow("pnpm audit:deps\n"), [
      "pnpm audit:licenses",
      "pnpm security:gates",
      "pnpm test:security-gates"
    ]);
    assert.deepEqual(validateSecurityDocs({ "docs/security.md": "pnpm audit:deps" }), [
      "docs/production-readiness.md: pnpm audit:deps",
      "docs/production-readiness.md: pnpm audit:licenses",
      "docs/production-readiness.md: pnpm audit:deps:snyk",
      "docs/production-readiness.md: pnpm audit:licenses:fossa",
      "docs/production-readiness.md: pnpm audit:licenses:scancode",
      "docs/security.md: pnpm audit:deps:snyk",
      "docs/security.md: pnpm audit:licenses",
      "docs/security.md: pnpm audit:licenses:fossa",
      "docs/security.md: pnpm audit:licenses:scancode",
      "docs/security.md: SNYK_TOKEN",
      "docs/security.md: FOSSA_API_KEY",
      "docs/security.md: artifacts/security/scancode.json"
    ]);
  });
});
