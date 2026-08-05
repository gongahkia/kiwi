#!/usr/bin/env node
import { execFile } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const rootDir = fileURLToPath(new URL("..", import.meta.url));
const [knownGoodRef, deltaPathInput] = process.argv.slice(2);

if (!knownGoodRef || !deltaPathInput || process.argv.length !== 4) {
  fail("usage: pnpm rollback:delta <known-good-ref> <data/deltas/yyyy-mm-dd/source.json>");
}

if (/[\0\r\n:]/u.test(knownGoodRef)) {
  fail("known-good ref must not contain colon or newline characters");
}

const deltaPath = normalizeDeltaPath(deltaPathInput);
const gitObject = `${knownGoodRef}:${deltaPath}`;
const reportPath = `reports/corpus-refresh/${deltaPath
  .replace(/^data\/deltas\//u, "")
  .replaceAll("/", "-")
  .replace(/\.json$/u, ".md")}`;

let stdout;
try {
  ({ stdout } = await execFileAsync("git", ["show", gitObject], {
    cwd: rootDir,
    maxBuffer: 64 * 1024 * 1024
  }));
} catch {
  fail(`could not read ${gitObject}`);
}

try {
  JSON.parse(stdout);
} catch {
  fail(`${gitObject} is not valid JSON`);
}

const outputPath = resolve(rootDir, deltaPath);
await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, stdout.endsWith("\n") ? stdout : `${stdout}\n`);

console.log(
  [
    `restored ${deltaPath} from ${knownGoodRef}`,
    "next:",
    `  pnpm --filter @wat/ingest summarize:delta ${deltaPath} ${reportPath}`,
    "  pnpm --filter @wat/ingest lint:sources",
    "  pnpm --filter @wat/search bench",
    "  pnpm typecheck"
  ].join("\n")
);

function normalizeDeltaPath(input) {
  const path = input.replaceAll("\\", "/");
  if (path.startsWith("/") || path.includes("..")) {
    fail("delta path must be repo-relative and must not contain '..'");
  }
  if (!/^data\/deltas\/\d{4}-\d{2}-\d{2}\/[^/]+\.json$/u.test(path)) {
    fail("delta path must match data/deltas/yyyy-mm-dd/source.json");
  }
  const resolved = resolve(rootDir, path);
  const deltasDir = resolve(rootDir, "data/deltas");
  if (!resolved.startsWith(`${deltasDir}/`)) {
    fail("delta path must stay under data/deltas");
  }
  return path;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
