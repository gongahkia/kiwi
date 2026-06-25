import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const root = resolve(dirname(scriptPath), "..");
const outputPath = join(root, "site", "integrity.json");

const files = [
  "site/pkg/kumeyuri_render_wasm.js",
  "site/pkg/kumeyuri_render_wasm_bg.wasm",
  "site/compat.json",
  "site/status.json",
  "site/favicon.svg",
  "packages/kumeyuri/wasm/kumeyuri_render_wasm.js",
  "packages/kumeyuri/wasm/kumeyuri_render_wasm_bg.wasm",
  "packages/kumeyuri/wasm/kumeyuri_render_wasm.d.ts",
];

export function buildIntegrityManifest() {
  return {
    generatedBy: "scripts/generate-integrity.mjs",
    files: files.map((path) => integrityEntry(path)),
  };
}

function integrityEntry(path) {
  const bytes = readFileSync(join(root, path));
  return {
    path,
    webPath: path.startsWith("site/") ? path.slice("site/".length) : null,
    bytes: bytes.length,
    sha256: createHash("sha256").update(bytes).digest("hex"),
    sri: `sha384-${createHash("sha384").update(bytes).digest("base64")}`,
  };
}

function manifestText(manifest) {
  return `${JSON.stringify(manifest, null, 2)}\n`;
}

function main() {
  const expected = manifestText(buildIntegrityManifest());
  if (process.argv.includes("--check")) {
    assert.ok(existsSync(outputPath), "site/integrity.json is missing");
    assert.equal(readFileSync(outputPath, "utf8"), expected, "site/integrity.json drifted");
    console.log("integrity ok");
    return;
  }
  writeFileSync(outputPath, expected);
  console.log("wrote site/integrity.json");
}

if (resolve(process.argv[1] ?? "") === scriptPath) {
  main();
}
