#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { JSDOM } from "jsdom";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const defaultManifest = join(repoRoot, "benches/compare/corpus/manifest.json");
const defaultResultsDir = join(repoRoot, "benches/compare/results");
const defaultOut = join(repoRoot, "benches/compare/results/fidelity.json");
const textTools = [
  "alexander-mermaid-ascii",
  "beautiful-mermaid",
  "kumeyuri",
  "mermaid2term",
  "pgavlin-mermaid-ascii",
];

function usage() {
  return `Usage:
  node benches/compare/tools/score-fidelity.mjs [--manifest FILE] [--results-dir DIR] [--out FILE]

Options:
  --manifest FILE     Corpus manifest. Defaults to benches/compare/corpus/manifest.json.
  --results-dir DIR   Adapter results directory. Defaults to benches/compare/results.
  --out FILE          JSON output path. Defaults to benches/compare/results/fidelity.json.
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
    out: defaultOut,
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
      case "--out":
        options.out = takeValue(args, index, arg);
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

function normalizeText(text) {
  return text
    .replace(/\s+/g, " ")
    .replace(/[^\p{L}\p{N} ]/gu, "")
    .trim()
    .toLowerCase();
}

function visibleLabels(svg) {
  const dom = new JSDOM(svg, { contentType: "image/svg+xml" });
  const candidates = [
    ...dom.window.document.querySelectorAll("text, tspan, span, foreignObject"),
  ].map((node) => normalizeText(node.textContent ?? ""));
  return [...new Set(candidates.filter((label) => label.length > 0))].sort();
}

async function readTextResult(resultsDir, tool, inputId) {
  const errorPath = join(resultsDir, tool, `${inputId}.error.txt`);
  try {
    const error = await readFile(errorPath, "utf8");
    return { status: "error", error: error.trim() };
  } catch {
  }

  const textPath = join(resultsDir, tool, `${inputId}.txt`);
  try {
    return { status: "ok", text: await readFile(textPath, "utf8"), path: textPath };
  } catch {
    return { status: "missing" };
  }
}

async function scoreTool(resultsDir, tool, inputId, labels) {
  const result = await readTextResult(resultsDir, tool, inputId);
  if (result.status !== "ok") {
    return result;
  }

  const normalizedOutput = normalizeText(result.text);
  const matched = labels.filter((label) => normalizedOutput.includes(label));
  return {
    status: "ok",
    path: result.path,
    labelCount: labels.length,
    matchedLabelCount: matched.length,
    labelRecall: labels.length === 0 ? 1 : matched.length / labels.length,
    missingLabels: labels.filter((label) => !matched.includes(label)),
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  const inputIds = await readManifest(options.manifest);
  const resultsDir = resolve(options.resultsDir);
  const scores = {};

  for (const inputId of inputIds) {
    const svgPath = join(resultsDir, "mermaid-cli", `${inputId}.svg`);
    let labels = [];
    try {
      labels = visibleLabels(await readFile(svgPath, "utf8"));
    } catch {
      scores[inputId] = { status: "missing-ground-truth", groundTruth: svgPath };
      continue;
    }

    scores[inputId] = {
      status: "ok",
      groundTruth: svgPath,
      labels,
      tools: {},
    };
    for (const tool of textTools) {
      scores[inputId].tools[tool] = await scoreTool(resultsDir, tool, inputId, labels);
    }
  }

  const payload = `${JSON.stringify({
    scorer: "svg-label-recall",
    manifest: resolve(options.manifest),
    resultsDir,
    scores,
  }, null, 2)}\n`;
  const out = resolve(options.out);
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, payload);
  process.stdout.write(payload);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
