#!/usr/bin/env node
import { readdir, readFile, stat } from "node:fs/promises";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const defaultManifest = join(repoRoot, "benches/compare/corpus/manifest.json");
const defaultResultsDir = join(repoRoot, "benches/compare/results");

function usage() {
  return `Usage:
  node benches/compare/tools/measure-output-sizes.mjs [--manifest FILE] [--results-dir DIR]

Options:
  --manifest FILE     Corpus manifest. Defaults to benches/compare/corpus/manifest.json.
  --results-dir DIR   Adapter results directory. Defaults to benches/compare/results.
`;
}

function takeValue(args, index, flag) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

function parseArgs(args) {
  const options = {
    manifest: defaultManifest,
    resultsDir: defaultResultsDir,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--manifest":
        options.manifest = takeValue(args, index, arg);
        index += 1;
        break;
      case "--results-dir":
        options.resultsDir = takeValue(args, index, arg);
        index += 1;
        break;
      default:
        throw new Error(`unknown option: ${arg}`);
    }
  }

  return options;
}

async function readManifest(manifestPath) {
  const manifest = JSON.parse(await readFile(resolve(manifestPath), "utf8"));
  if (!Array.isArray(manifest.inputs)) {
    throw new Error("manifest has no inputs array");
  }
  return manifest.inputs.map((entry) => entry.id);
}

function lineCount(text) {
  if (text.length === 0) return 0;
  return text.endsWith("\n") ? text.split("\n").length - 1 : text.split("\n").length;
}

async function readToolResult(toolDir, inputId) {
  const files = await readdir(toolDir);
  const success = files.find((file) => basename(file, extname(file)) === inputId && !file.endsWith(".error.txt"));
  if (success) {
    const path = join(toolDir, success);
    const content = await readFile(path, "utf8");
    const stats = await stat(path);
    return {
      status: "ok",
      path,
      extension: extname(path).slice(1),
      bytes: stats.size,
      chars: content.length,
      lines: lineCount(content),
    };
  }

  const error = files.find((file) => file === `${inputId}.error.txt`);
  if (error) {
    const path = join(toolDir, error);
    const content = await readFile(path, "utf8");
    return {
      status: "error",
      path,
      error: content.trim(),
    };
  }

  return { status: "missing" };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  const inputIds = await readManifest(options.manifest);
  const resultsDir = resolve(options.resultsDir);
  const toolNames = (await readdir(resultsDir, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  const tools = {};
  for (const tool of toolNames) {
    const toolDir = join(resultsDir, tool);
    tools[tool] = {};
    for (const inputId of inputIds) {
      tools[tool][inputId] = await readToolResult(toolDir, inputId);
    }
  }

  process.stdout.write(`${JSON.stringify({
    manifest: resolve(options.manifest),
    resultsDir,
    tools,
  }, null, 2)}\n`);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
