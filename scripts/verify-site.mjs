import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { buildIntegrityManifest } from "./generate-integrity.mjs";

const root = process.cwd();
const site = join(root, "site");

for (const path of [
  "index.html",
  "styles.css",
  "playground.js",
  "compat.json",
  "parity.json",
  "motion.json",
  "integrity.json",
  "status.json",
  "favicon.svg",
  ".nojekyll",
  "CNAME",
  "pkg/kumeyuri_render_wasm.js",
  "pkg/kumeyuri_render_wasm_bg.wasm",
]) {
  assert.equal(existsSync(join(site, path)), true, `missing site/${path}`);
}

for (const path of [
  "wasm/kumeyuri_render_wasm.js",
  "wasm/kumeyuri_render_wasm.d.ts",
  "wasm/kumeyuri_render_wasm_bg.wasm",
]) {
  assert.equal(existsSync(join(root, "packages/kumeyuri", path)), true, `missing packages/kumeyuri/${path}`);
}

const index = readFileSync(join(site, "index.html"), "utf8");
for (const text of [
  "npm install kumeyuri",
  "kumeyuri/wasm",
  "playground-copy",
  "playground-download",
  "Adoption Gallery",
  "Mermaid Parity",
  "Animation Quality",
  "Distribution Trust",
  "Regression Dashboard",
]) {
  assert.ok(index.includes(text), `site/index.html missing ${text}`);
}

const packageJson = JSON.parse(readFileSync(join(root, "packages/kumeyuri/package.json"), "utf8"));
assert.equal(packageJson.exports["./wasm"].import, "./wasm/kumeyuri_render_wasm.js");
assert.ok(packageJson.files.includes("wasm"));

const actualCompat = JSON.parse(readFileSync(join(site, "compat.json"), "utf8"));
const expectedCompat = JSON.parse(
  execFileSync("cargo", ["run", "-q", "-p", "kumeyuri-cli", "--", "compat", "--json"], {
    cwd: root,
    encoding: "utf8",
  }),
);
assert.deepEqual(actualCompat, expectedCompat, "site/compat.json drifted from kumeyuri compat --json");

const status = JSON.parse(readFileSync(join(site, "status.json"), "utf8"));
assert.equal(status.compat.families, actualCompat.counts.families);
assert.equal(status.compat.rootSpellings, actualCompat.counts.rootSpellings);
assert.equal(status.compat.animatedPartial, actualCompat.counts.animatedPartial);
assert.equal(status.compat.staticOnlyPartial, actualCompat.counts.staticOnlyPartial);
assert.equal(status.compat.unsupported, actualCompat.counts.unsupported);

const parity = JSON.parse(readFileSync(join(site, "parity.json"), "utf8"));
assert.equal(parity.counts.fixtures, actualCompat.counts.families);
assert.equal(parity.counts.kumeyuriParsed, actualCompat.counts.families);
assert.equal(parity.counts.kumeyuriRendered, actualCompat.counts.families);
assert.equal(parity.counts.animatedPartial, actualCompat.counts.animatedPartial);
assert.equal(parity.counts.staticOnlyPartial, actualCompat.counts.staticOnlyPartial);
assert.equal(parity.counts.unsupported, actualCompat.counts.unsupported);
assert.equal(status.parity.fixtures, parity.counts.fixtures);
assert.equal(status.parity.kumeyuriRendered, parity.counts.kumeyuriRendered);
assert.equal(status.parity.mermaidRendered, parity.counts.mermaidRendered);
assert.equal(status.parity.deltas, parity.counts.deltas);

const motion = JSON.parse(readFileSync(join(site, "motion.json"), "utf8"));
assert.equal(motion.counts.families, actualCompat.counts.families);
assert.equal(motion.counts.animatedPartial, actualCompat.counts.animatedPartial);
assert.equal(motion.counts.staticOnlyPartial, actualCompat.counts.staticOnlyPartial);
assert.equal(motion.counts.failures, 0);
assert.equal(status.motion.failures, motion.counts.failures);
assert.equal(status.motion.animatedPartial, motion.counts.animatedPartial);
assert.equal(status.releaseTrust.npmProvenance, true);
assert.equal(status.releaseTrust.npmTrustedPublishingWorkflow, true);
assert.equal(status.releaseTrust.sbom, true);
assert.equal(status.releaseTrust.sriManifest, true);

const actualIntegrity = JSON.parse(readFileSync(join(site, "integrity.json"), "utf8"));
assert.deepEqual(actualIntegrity, buildIntegrityManifest(), "site/integrity.json drifted");

console.log("site ok");
