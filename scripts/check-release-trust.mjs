import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";

const root = process.cwd();
const releaseWorkflow = readFileSync(join(root, ".github/workflows/release.yml"), "utf8");
const npmWorkflow = readFileSync(join(root, ".github/workflows/npm-publish.yml"), "utf8");
const distConfig = readFileSync(join(root, "dist-workspace.toml"), "utf8");

assert.match(releaseWorkflow, /id-token": "write"|id-token:\s*write/, "release workflow must grant OIDC id-token");
assert.match(releaseWorkflow, /attestations": "write"|attestations:\s*write/, "release workflow must grant attestations");
assert.match(releaseWorkflow, /actions\/attest@/, "release workflow must generate GitHub attestations");
assert.match(releaseWorkflow, /cosign sign-blob/, "release workflow must sign release artifacts");
assert.match(releaseWorkflow, /publish-homebrew-formula:/, "release workflow must publish the Homebrew formula");
assert.match(releaseWorkflow, /repository:\s*"gongahkia\/homebrew-kumeyuri"/, "release workflow must publish to the Homebrew tap");
assert.match(releaseWorkflow, /secrets\.HOMEBREW_TAP_TOKEN/, "release workflow must use the Homebrew tap token");

assert.match(distConfig, /installers\s*=\s*\[[^\]]*"homebrew"/s, "dist config must build a Homebrew formula");
assert.match(distConfig, /tap\s*=\s*"gongahkia\/homebrew-kumeyuri"/, "dist config must target the Homebrew tap");
assert.match(distConfig, /publish-jobs\s*=\s*\[[^\]]*"homebrew"/s, "dist config must publish Homebrew updates");

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
