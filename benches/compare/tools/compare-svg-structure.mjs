#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { JSDOM } from "jsdom";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const defaultManifest = join(repoRoot, "benches/compare/corpus/benchmark-manifest.json");
const defaultResultsDir = join(repoRoot, "benches/compare/results");
const defaultOut = join(defaultResultsDir, "svg-structure.json");
const trackedTags = ["circle", "ellipse", "foreignObject", "g", "line", "path", "polygon", "polyline", "rect", "text", "tspan"];

function usage() {
  return `Usage:
  node benches/compare/tools/compare-svg-structure.mjs [--manifest FILE] [--results-dir DIR] [--out FILE] [--require-all]

Compares KumeYuri and Mermaid CLI SVG structure. This is a semantic structural
report, not a pixel-perfect visual-diff assertion.

Options:
  --manifest FILE    Pinned corpus manifest. Defaults to benchmark-manifest.json.
  --results-dir DIR  Parent directory containing kumeyuri/ and mermaid-cli/ output.
  --out FILE         JSON report path.
  --require-all      Return nonzero when either renderer has missing or invalid SVG output.
`;
}

function takeValue(args, index, flag) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value`);
  return value;
}

function parseArgs(args) {
  const options = {
    manifest: defaultManifest,
    resultsDir: defaultResultsDir,
    out: defaultOut,
    requireAll: false,
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
      case "--require-all":
        options.requireAll = true;
        break;
      default:
        throw new Error(`unknown option: ${arg}`);
    }
  }
  return options;
}

function normalizeText(text) {
  return text
    .replace(/\s+/g, " ")
    .replace(/[^\p{L}\p{N} ]/gu, "")
    .trim()
    .toLowerCase();
}

function uniqueLabels(document) {
  const nodes = document.querySelectorAll("text, tspan, foreignObject");
  return [...new Set([...nodes]
    .map((node) => normalizeText(node.textContent ?? ""))
    .filter(Boolean))].sort();
}

function countTags(document) {
  return Object.fromEntries(trackedTags.map((tag) => [tag, document.querySelectorAll(tag).length]));
}

function parseSvg(svg, path) {
  const dom = new JSDOM(svg, { contentType: "image/svg+xml" });
  const root = dom.window.document.documentElement;
  if (root.localName !== "svg") throw new Error(`${path} has no SVG root`);
  const tags = countTags(dom.window.document);
  return {
    path,
    labels: uniqueLabels(dom.window.document),
    tagCounts: tags,
    elementCount: dom.window.document.querySelectorAll("*").length,
    viewBox: root.getAttribute("viewBox"),
    width: root.getAttribute("width"),
    height: root.getAttribute("height"),
    titleCount: root.querySelectorAll("title").length,
    descriptionCount: root.querySelectorAll("desc").length,
  };
}

function jaccard(left, right) {
  const leftSet = new Set(left);
  const rightSet = new Set(right);
  const union = new Set([...leftSet, ...rightSet]);
  if (union.size === 0) return 1;
  let intersection = 0;
  for (const value of leftSet) if (rightSet.has(value)) intersection += 1;
  return intersection / union.size;
}

function labelComparison(kumeyuri, mermaid) {
  const kumeyuriSet = new Set(kumeyuri.labels);
  const mermaidSet = new Set(mermaid.labels);
  const matched = mermaid.labels.filter((label) => kumeyuriSet.has(label));
  return {
    mermaidLabelCount: mermaid.labels.length,
    kumeyuriLabelCount: kumeyuri.labels.length,
    matchedLabelCount: matched.length,
    kumeyuriRecallOfMermaidLabels: mermaid.labels.length === 0 ? 1 : matched.length / mermaid.labels.length,
    kumeyuriPrecisionOfMermaidLabels: kumeyuri.labels.length === 0 ? 1 : matched.length / kumeyuri.labels.length,
    labelJaccard: jaccard(kumeyuri.labels, mermaid.labels),
    missingFromKumeyuri: mermaid.labels.filter((label) => !kumeyuriSet.has(label)),
  };
}

function tagComparison(kumeyuri, mermaid) {
  const tags = {};
  for (const tag of trackedTags) {
    const left = kumeyuri.tagCounts[tag];
    const right = mermaid.tagCounts[tag];
    tags[tag] = { kumeyuri: left, mermaid: right, delta: left - right };
  }
  const max = Math.max(kumeyuri.elementCount, mermaid.elementCount, 1);
  return {
    tags,
    elementCountRatio: Math.min(kumeyuri.elementCount, mermaid.elementCount) / max,
    kumeyuriHasAccessibleName: kumeyuri.titleCount > 0 || kumeyuri.descriptionCount > 0,
    mermaidHasAccessibleName: mermaid.titleCount > 0 || mermaid.descriptionCount > 0,
  };
}

async function readSvg(resultsDir, renderer, id) {
  const path = join(resultsDir, renderer, `${id}.svg`);
  try {
    return { status: "ok", svg: parseSvg(await readFile(path, "utf8"), path) };
  } catch (error) {
    return { status: "error", path, error: error instanceof Error ? error.message : String(error) };
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return 0;
  }
  const manifestPath = resolve(options.manifest);
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  if (!Array.isArray(manifest.inputs)) throw new Error(`manifest has no inputs array: ${manifestPath}`);
  const resultsDir = resolve(options.resultsDir);
  const comparisons = [];
  for (const entry of manifest.inputs) {
    const kumeyuri = await readSvg(resultsDir, "kumeyuri", entry.id);
    const mermaid = await readSvg(resultsDir, "mermaid-cli", entry.id);
    if (kumeyuri.status !== "ok" || mermaid.status !== "ok") {
      comparisons.push({ id: entry.id, root: entry.root, status: "error", kumeyuri, mermaid });
      continue;
    }
    comparisons.push({
      id: entry.id,
      root: entry.root,
      status: "ok",
      kumeyuri: kumeyuri.svg,
      mermaid: mermaid.svg,
      comparison: {
        labels: labelComparison(kumeyuri.svg, mermaid.svg),
        structure: tagComparison(kumeyuri.svg, mermaid.svg),
      },
    });
  }
  const payload = {
    schemaVersion: 1,
    comparator: "svg-structure-v1",
    manifest: manifestPath,
    resultsDir,
    comparisons,
  };
  const output = resolve(options.out);
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(payload, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
  return options.requireAll && comparisons.some((comparison) => comparison.status !== "ok") ? 1 : 0;
}

main().then((exitCode) => {
  process.exitCode = exitCode;
}).catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
