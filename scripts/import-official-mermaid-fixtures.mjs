#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(scriptPath), "..");
const corpusDir = path.join(root, "tests/fuzz/official-mermaid");
const manifestPath = path.join(corpusDir, "manifest.json");
const generatedBy = "scripts/import-official-mermaid-fixtures.mjs";
const mermaidVersion = "11.15.0";
const validStatuses = new Set(["pass", "fail", "unsupported"]);
const args = new Set(process.argv.slice(2));

if (args.has("--help")) {
  console.log("usage: node scripts/import-official-mermaid-fixtures.mjs [--check]");
  process.exit(0);
}

for (const arg of args) {
  if (arg !== "--check") {
    console.error(`unknown argument: ${arg}`);
    process.exit(2);
  }
}

const fixtures = [
  ["flowchart.mmd", "https://mermaid.js.org/syntax/flowchart.html", "flowchart"],
  ["sequence.mmd", "https://mermaid.js.org/syntax/sequenceDiagram.html", "sequenceDiagram"],
  ["state.mmd", "https://mermaid.js.org/syntax/stateDiagram.html", "stateDiagram-v2"],
  ["class.mmd", "https://mermaid.js.org/syntax/classDiagram.html", "classDiagram"],
  ["er.mmd", "https://mermaid.js.org/syntax/entityRelationshipDiagram.html", "erDiagram"],
  ["gantt.mmd", "https://mermaid.js.org/syntax/gantt.html", "gantt"],
  ["pie.mmd", "https://mermaid.js.org/syntax/pie.html", "pie"],
  ["quadrant.mmd", "https://mermaid.js.org/syntax/quadrantChart.html", "quadrantChart"],
  ["requirement.mmd", "https://mermaid.js.org/syntax/requirementDiagram.html", "requirementDiagram"],
  ["cynefin.mmd", "https://mermaid.js.org/syntax/cynefin.html", "cynefin-beta"],
  ["gitgraph.mmd", "https://mermaid.js.org/syntax/gitgraph.html", "gitGraph"],
  ["c4.mmd", "https://mermaid.js.org/syntax/c4.html", "C4Container"],
  ["mindmap.mmd", "https://mermaid.js.org/syntax/mindmap.html", "mindmap"],
  ["timeline.mmd", "https://mermaid.js.org/syntax/timeline.html", "timeline"],
  ["zenuml.mmd", "https://mermaid.ai/open-source/syntax/zenuml.html", "zenuml"],
  ["sankey.mmd", "https://mermaid.js.org/syntax/sankey.html", "sankey-beta"],
  ["xychart.mmd", "https://mermaid.js.org/syntax/xyChart.html", "xychart-beta"],
  ["block.mmd", "https://mermaid.js.org/syntax/block.html", "block"],
  ["packet.mmd", "https://mermaid.js.org/syntax/packet.html", "packet"],
  ["kanban.mmd", "https://mermaid.js.org/syntax/kanban.html", "kanban"],
  ["architecture.mmd", "https://mermaid.js.org/syntax/architecture.html", "architecture-beta"],
  ["radar.mmd", "https://mermaid.js.org/syntax/radar.html", "radar-beta"],
  ["railroad.mmd", "https://mermaid.js.org/syntax/railroad.html", "railroad-diagram"],
  ["swimlanes.mmd", "https://mermaid.js.org/syntax/swimlanes.html", "swimlane"],
  ["eventmodeling.mmd", "https://mermaid.ai/open-source/syntax/eventmodeling.html", "eventmodeling"],
  ["treemap.mmd", "https://mermaid.js.org/syntax/treemap.html", "treemap-beta"],
  ["venn.mmd", "https://mermaid.js.org/syntax/venn.html", "venn-beta"],
  ["ishikawa.mmd", "https://mermaid.js.org/syntax/ishikawa.html", "ishikawa-beta"],
  ["wardley.mmd", "https://mermaid.js.org/syntax/wardley.html", "wardley-beta"],
  ["tree_view.mmd", "https://mermaid.js.org/syntax/treeView.html", "treeView-beta"],
  ["journey.mmd", "https://mermaid.js.org/syntax/userJourney.html", "journey"],
].map(([file, sourceUrl, rootType]) => ({
  file,
  sourceUrl,
  rootType,
  expectedParserStatus: "pass",
  expectedRenderStatus: "pass",
}));

for (const fixture of fixtures) {
  validateFixture(fixture);
}

const manifest = {
  schemaVersion: 1,
  generatedBy,
  mermaidVersion,
  fixtures: fixtures.map((fixture) => ({
    fixturePath: path.posix.join("tests/fuzz/official-mermaid", fixture.file),
    sourceUrl: fixture.sourceUrl,
    mermaidVersion,
    rootType: fixture.rootType,
    expectedParserStatus: fixture.expectedParserStatus,
    expectedRenderStatus: fixture.expectedRenderStatus,
  })),
};

const expected = `${JSON.stringify(manifest, null, 2)}\n`;

if (args.has("--check")) {
  if (readFileSync(manifestPath, "utf8") !== expected) {
    console.error(`stale official Mermaid fixture manifest: ${relative(manifestPath)}`);
    process.exit(1);
  }
  console.log("official Mermaid fixture corpus is current");
} else {
  writeFileSync(manifestPath, expected);
  console.log(`wrote ${relative(manifestPath)}`);
}

function validateFixture(fixture) {
  if (!fixture.file.endsWith(".mmd")) {
    throw new Error(`fixture file must end with .mmd: ${fixture.file}`);
  }
  if (!fixture.sourceUrl.startsWith("https://mermaid.js.org/") && !fixture.sourceUrl.startsWith("https://mermaid.ai/")) {
    throw new Error(`fixture source URL must be official Mermaid docs: ${fixture.file}`);
  }
  if (!validStatuses.has(fixture.expectedParserStatus)) {
    throw new Error(`invalid parser status for ${fixture.file}`);
  }
  if (!validStatuses.has(fixture.expectedRenderStatus)) {
    throw new Error(`invalid render status for ${fixture.file}`);
  }
  const filePath = path.join(corpusDir, fixture.file);
  if (!existsSync(filePath)) {
    throw new Error(`missing fixture file: ${relative(filePath)}`);
  }
}

function relative(filePath) {
  return path.relative(root, filePath);
}
