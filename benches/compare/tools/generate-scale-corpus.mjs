#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const corpusDir = join(repoRoot, "benches/compare/corpus");
const scaleDir = join(corpusDir, "scales");
const baseManifestPath = join(corpusDir, "manifest.json");
const scaleManifestPath = join(scaleDir, "manifest.json");
const benchmarkManifestPath = join(corpusDir, "benchmark-manifest.json");
const flowchartSizes = [10, 50, 100, 250, 500];

function usage() {
  return `Usage:
  node benches/compare/tools/generate-scale-corpus.mjs --write
  node benches/compare/tools/generate-scale-corpus.mjs --check

Generates deterministic scale fixtures and manifests. --check fails when a
checked-in fixture or manifest differs from the generator output.
`;
}

function parseArgs(args) {
  const options = { write: false, check: false };
  for (const arg of args) {
    if (arg === "--write") options.write = true;
    else if (arg === "--check") options.check = true;
    else if (arg === "--help" || arg === "-h") options.help = true;
    else throw new Error(`unknown option: ${arg}`);
  }
  if (!options.help && options.write === options.check) {
    throw new Error("pass exactly one of --write or --check");
  }
  return options;
}

function nodeId(index) {
  return `N${String(index).padStart(3, "0")}`;
}

function flowNode(index, label) {
  return `${nodeId(index)}[\"${label}\"]`;
}

function flowchartSource(pattern, nodes) {
  const lines = [
    `%% benchmark: kind=flowchart pattern=${pattern} nodes=${nodes}`,
    "graph TD",
  ];
  const labels = Array.from({ length: nodes }, (_, index) => {
    const label = pattern === "nested-subgraphs-long-labels"
      ? `Node ${index + 1}: a deliberately long label for width, wrapping, and routing pressure`
      : `${pattern} node ${index + 1}`;
    return flowNode(index, label);
  });

  if (pattern === "nested-subgraphs-long-labels") {
    const depth = Math.min(5, Math.max(2, Math.floor(Math.log10(nodes)) + 2));
    for (let level = 0; level < depth; level += 1) {
      lines.push(`subgraph Group_${level}[\"Nested group ${level + 1} with a deliberately long descriptive label\"]`);
    }
    lines.push(...labels.map((label) => `  ${label}`));
    for (let index = 0; index < nodes - 1; index += 1) {
      lines.push(`  ${nodeId(index)} -->|\"long transition ${index + 1}\"| ${nodeId(index + 1)}`);
    }
    for (let level = 0; level < depth; level += 1) lines.push("end");
    return `${lines.join("\n")}\n`;
  }

  lines.push(...labels);
  if (pattern === "chain") {
    for (let index = 0; index < nodes - 1; index += 1) lines.push(`${nodeId(index)} --> ${nodeId(index + 1)}`);
  } else if (pattern === "tree") {
    for (let index = 1; index < nodes; index += 1) lines.push(`${nodeId(Math.floor((index - 1) / 2))} --> ${nodeId(index)}`);
  } else if (pattern === "fan-out") {
    for (let index = 1; index < nodes; index += 1) lines.push(`${nodeId(0)} --> ${nodeId(index)}`);
  } else if (pattern === "fan-in") {
    for (let index = 0; index < nodes - 1; index += 1) lines.push(`${nodeId(index)} --> ${nodeId(nodes - 1)}`);
  } else if (pattern === "cyclic") {
    for (let index = 0; index < nodes; index += 1) lines.push(`${nodeId(index)} --> ${nodeId((index + 1) % nodes)}`);
  } else {
    throw new Error(`unknown flowchart pattern: ${pattern}`);
  }
  return `${lines.join("\n")}\n`;
}

function sequenceSource(participants, messages) {
  const lines = [
    `%% benchmark: kind=sequence participants=${participants} messages=${messages}`,
    "sequenceDiagram",
  ];
  for (let index = 0; index < participants; index += 1) {
    lines.push(`participant P${index + 1} as Service ${index + 1}`);
  }

  let message = 0;
  let batch = 0;
  while (message < messages) {
    const remaining = messages - message;
    const batchSize = Math.min(50, remaining);
    const primaryCount = Math.ceil(batchSize / 2);
    lines.push(`loop Batch ${batch + 1}`);
    lines.push("  alt Primary path");
    lines.push("    critical protected operation");
    for (let offset = 0; offset < batchSize; offset += 1, message += 1) {
      const from = message % participants;
      const to = offset < primaryCount
        ? (from + 1) % participants
        : (from + participants - 1) % participants;
      const arrow = offset < primaryCount ? "->>" : "-->>";
      lines.push(`      P${from + 1}${arrow}P${to + 1}: message ${String(message + 1).padStart(3, "0")}`);
      if (message % 10 === 0) {
        lines.push(`      activate P${to + 1}`);
        lines.push(`      deactivate P${to + 1}`);
      }
    }
    lines.push("    end");
    lines.push("  Note over P1: batch checkpoint");
    lines.push("end");
    batch += 1;
  }
  return `${lines.join("\n")}\n`;
}

function stateSource(depth) {
  const lines = [
    `%% benchmark: kind=state nested_depth=${depth}`,
    "stateDiagram-v2",
  ];
  for (let level = 0; level < depth; level += 1) {
    lines.push(`${"  ".repeat(level)}state Level_${String(level + 1).padStart(2, "0")} {`);
  }
  const indent = "  ".repeat(depth);
  lines.push(`${indent}[*] --> Working`);
  lines.push(`${indent}Working --> Waiting: checkpoint`);
  lines.push(`${indent}Waiting --> [*]: complete`);
  for (let level = depth - 1; level >= 0; level -= 1) lines.push(`${"  ".repeat(level)}}`);
  lines.push("[*] --> Level_01");
  lines.push("Level_01 --> [*]");
  return `${lines.join("\n")}\n`;
}

function scaleFixtures() {
  const fixtures = [];
  const patterns = ["chain", "tree", "fan-out", "fan-in", "cyclic", "nested-subgraphs-long-labels"];
  for (const nodes of flowchartSizes) {
    for (const pattern of patterns) {
      const id = `flowchart-${pattern}-${nodes}`;
      fixtures.push({
        id,
        root: "flowchart",
        path: `${id}.mmd`,
        content: flowchartSource(pattern, nodes),
        reason: `${nodes}-node ${pattern} flowchart scale fixture`,
      });
    }
  }
  for (const [participants, messages] of [[5, 100], [10, 250], [20, 500]]) {
    const id = `sequence-${participants}p-${messages}m`;
    fixtures.push({
      id,
      root: "sequenceDiagram",
      path: `${id}.mmd`,
      content: sequenceSource(participants, messages),
      reason: `${participants} participants, ${messages} messages, activations, and nested controls`,
    });
  }
  for (const depth of [5, 10, 20]) {
    const id = `state-nested-depth-${depth}`;
    fixtures.push({
      id,
      root: "stateDiagram-v2",
      path: `${id}.mmd`,
      content: stateSource(depth),
      reason: `${depth}-level nested state hierarchy`,
    });
  }
  return fixtures;
}

function stringify(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

async function assertEqual(path, expected) {
  let actual;
  try {
    actual = await readFile(path, "utf8");
  } catch {
    throw new Error(`missing generated file: ${path}`);
  }
  if (actual !== expected) throw new Error(`generated file drifted: ${path}`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  const baseManifest = JSON.parse(await readFile(baseManifestPath, "utf8"));
  if (!Array.isArray(baseManifest.inputs)) throw new Error("base corpus manifest has no inputs array");
  const fixtures = scaleFixtures();
  const scaleManifest = {
    version: 1,
    generatedBy: "benches/compare/tools/generate-scale-corpus.mjs",
    inputs: fixtures.map(({ content, ...entry }) => entry),
  };
  const benchmarkManifest = {
    version: 1,
    generatedBy: "benches/compare/tools/generate-scale-corpus.mjs",
    inputs: [
      ...baseManifest.inputs,
      ...fixtures.map(({ content, path, ...entry }) => ({ ...entry, path: `scales/${path}` })),
    ],
  };

  if (options.write) {
    await mkdir(scaleDir, { recursive: true });
    for (const fixture of fixtures) await writeFile(join(scaleDir, fixture.path), fixture.content);
    await writeFile(scaleManifestPath, stringify(scaleManifest));
    await writeFile(benchmarkManifestPath, stringify(benchmarkManifest));
    process.stdout.write(`wrote ${fixtures.length} scale fixtures and benchmark-manifest.json\n`);
    return;
  }

  for (const fixture of fixtures) await assertEqual(join(scaleDir, fixture.path), fixture.content);
  await assertEqual(scaleManifestPath, stringify(scaleManifest));
  await assertEqual(benchmarkManifestPath, stringify(benchmarkManifest));
  process.stdout.write(`scale corpus ok (${fixtures.length} fixtures)\n`);
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
