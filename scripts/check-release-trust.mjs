import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";

const root = process.cwd();
const releaseWorkflow = readFileSync(join(root, ".github/workflows/release.yml"), "utf8");
const signWorkflow = readFileSync(join(root, ".github/workflows/sign-release-artifacts.yml"), "utf8");
const npmWorkflow = readFileSync(join(root, ".github/workflows/npm-publish.yml"), "utf8");

assert.match(releaseWorkflow, /id-token": "write"|id-token:\s*write/, "release workflow must grant OIDC id-token");
assert.match(releaseWorkflow, /attestations": "write"|attestations:\s*write/, "release workflow must grant attestations");
assert.match(releaseWorkflow, /actions\/attest@/, "release workflow must generate GitHub attestations");
assert.match(releaseWorkflow, /cosign sign-blob/, "release workflow must sign release artifacts");
assert.doesNotMatch(releaseWorkflow, /- name: Sign release artifacts\s*\n\s*if:\s*\$\{\{\s*!github\.event\.repository\.private\s*\}\}/, "release artifact signing must not skip private repositories");
assert.match(signWorkflow, /workflow_dispatch:/, "release signing workflow must support manual dispatch");
assert.match(signWorkflow, /id-token:\s*write/, "release signing workflow must grant OIDC id-token");
assert.match(signWorkflow, /contents:\s*write/, "release signing workflow must upload release bundles");
assert.match(signWorkflow, /cosign sign-blob/, "release signing workflow must sign release artifacts");
assert.match(signWorkflow, /gh release upload/, "release signing workflow must upload sigstore bundles");

assert.match(npmWorkflow, /id-token:\s*write/, "npm workflow must grant OIDC id-token");
assert.doesNotMatch(npmWorkflow, /NODE_AUTH_TOKEN|NPM_TOKEN/, "npm workflow must not require long-lived npm tokens");
assert.match(npmWorkflow, /npm publish .*--provenance/, "npm workflow must publish with provenance");
assert.match(npmWorkflow, /npm sbom/, "npm workflow must emit an npm SBOM");

for (const packagePath of workspacePackageJsonPaths()) {
  const packageJson = JSON.parse(readFileSync(packagePath, "utf8"));
  if (packageJson.private) {
    continue;
  }
  assert.equal(packageJson.publishConfig?.provenance, true, `${relative(packagePath)} missing publishConfig.provenance`);
  assert.equal(packageJson.publishConfig?.access, "public", `${relative(packagePath)} missing publishConfig.access=public`);
}

console.log("release trust ok");

function workspacePackageJsonPaths() {
  const packageJson = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
  return packageJson.workspaces.flatMap((workspace) => {
    const directory = workspace.endsWith("/*") ? workspace.slice(0, -2) : workspace;
    if (!workspace.endsWith("/*")) {
      return [join(root, directory, "package.json")];
    }
    return readdirSync(join(root, directory), { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => join(root, directory, entry.name, "package.json"));
  });
}

function relative(filePath) {
  return resolve(filePath).slice(root.length + 1);
}
