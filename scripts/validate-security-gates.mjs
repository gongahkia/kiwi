#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const requiredSecurityScripts = {
  "audit:deps": "pnpm audit --audit-level high",
  "audit:deps:snyk": "snyk test --all-projects --severity-threshold=high",
  "audit:licenses": "pnpm licenses list --prod",
  "audit:licenses:fossa": "fossa analyze && fossa test",
  "audit:licenses:scancode":
    "scancode --license --copyright --package --json-pp artifacts/security/scancode.json .",
  "security:gates": "node scripts/validate-security-gates.mjs",
  "test:security-gates": "node --test scripts/validate-security-gates.test.mjs"
};

export const requiredSecurityWorkflowCommands = [
  "pnpm audit:deps",
  "pnpm audit:licenses",
  "pnpm security:gates",
  "pnpm test:security-gates"
];

export const requiredSecurityDocTokens = {
  "docs/production-readiness.md": [
    "pnpm audit:deps",
    "pnpm audit:licenses",
    "pnpm audit:deps:snyk",
    "pnpm audit:licenses:fossa",
    "pnpm audit:licenses:scancode"
  ],
  "docs/security.md": [
    "pnpm audit:deps",
    "pnpm audit:deps:snyk",
    "pnpm audit:licenses",
    "pnpm audit:licenses:fossa",
    "pnpm audit:licenses:scancode",
    "SNYK_TOKEN",
    "FOSSA_API_KEY",
    "artifacts/security/scancode.json"
  ]
};

export function validateSecurityScripts(packageJsonText) {
  const packageJson = JSON.parse(packageJsonText);
  const scripts = packageJson.scripts ?? {};
  return Object.entries(requiredSecurityScripts)
    .filter(([name, command]) => scripts[name] !== command)
    .map(([name, command]) => `${name}: ${command}`);
}

export function validateSecurityWorkflow(workflowText) {
  return requiredSecurityWorkflowCommands.filter((command) => !workflowText.includes(command));
}

export function validateSecurityDocs(docs) {
  const missing = [];
  for (const [path, tokens] of Object.entries(requiredSecurityDocTokens)) {
    const text = docs[path] ?? "";
    for (const token of tokens) {
      if (!text.includes(token)) missing.push(`${path}: ${token}`);
    }
  }
  return missing;
}

export function validateSecurityGates(inputs) {
  const missingPackageScripts = validateSecurityScripts(inputs.packageJsonText);
  const missingWorkflowCommands = validateSecurityWorkflow(inputs.workflowText);
  const missingDocTokens = validateSecurityDocs(inputs.docs);
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
  const result = validateSecurityGates({
    docs: readDocs(Object.keys(requiredSecurityDocTokens)),
    packageJsonText: readFileSync("package.json", "utf8"),
    workflowText: readFileSync(".github/workflows/ci.yml", "utf8")
  });
  if (!result.ok) {
    for (const item of result.missingPackageScripts)
      console.error(`missing security package script: ${item}`);
    for (const item of result.missingWorkflowCommands)
      console.error(`missing security workflow command: ${item}`);
    for (const item of result.missingDocTokens)
      console.error(`missing security doc token: ${item}`);
    process.exit(1);
  }
  console.log("security gate coverage ok");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
