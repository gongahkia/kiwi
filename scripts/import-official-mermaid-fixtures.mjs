#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
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
  {
    file: "flowchart.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/flowchart.html",
    rootType: "flowchart",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid flowchart examples
%%{ init: { 'theme': 'base' } }%%
flowchart LR
A[Start] --> B{Ready?}
B -- Yes --> C[Ship]
B -- No --> D[Retry]
subgraph group [Generated Group]
direction TB
D --> A
end
classDef warning fill:#f96,stroke:#333,stroke-width:2px
class B warning
`,
  },
  {
    file: "sequence.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/sequenceDiagram.html",
    rootType: "sequence",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid sequence examples
%%{ init: { 'theme': 'base' } }%%
sequenceDiagram
participant Alice as Alice Doe
actor Bob
Alice->>Bob: Request
Bob-->>Alice: Response
Note over Alice,Bob: Shared context
loop Retry
Alice->Bob: Ping
alt Success
Bob-->>Alice: OK
opt Cache
Alice--)Bob: Open message
par Worker
Alice-xBob: Stop
`,
  },
  {
    file: "state.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/stateDiagram.html",
    rootType: "state",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid state examples
%%{ init: { 'theme': 'base' } }%%
stateDiagram-v2
direction LR
[*] --> Idle: boot
state "Active Work" as Active
Idle --> Active: start
state Choice <<choice>>
Active --> Choice
Choice --> [*]: done
state Composite {
}
`,
  },
];

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

const outputs = [
  ...fixtures.map((fixture) => ({
    filePath: path.join(corpusDir, fixture.file),
    contents: fixture.source,
  })),
  {
    filePath: manifestPath,
    contents: `${JSON.stringify(manifest, null, 2)}\n`,
  },
];

if (args.has("--check")) {
  let failed = false;
  for (const output of outputs) {
    const current = await readExisting(output.filePath);
    if (current !== output.contents) {
      failed = true;
      console.error(`stale official Mermaid fixture output: ${relative(output.filePath)}`);
    }
  }
  if (failed) {
    process.exit(1);
  }
  console.log("official Mermaid fixture corpus is current");
} else {
  await mkdir(corpusDir, { recursive: true });
  for (const output of outputs) {
    await writeFile(output.filePath, output.contents);
    console.log(`wrote ${relative(output.filePath)}`);
  }
}

function validateFixture(fixture) {
  if (!fixture.file.endsWith(".mmd")) {
    throw new Error(`fixture file must end with .mmd: ${fixture.file}`);
  }
  if (!fixture.sourceUrl.startsWith("https://mermaid.js.org/")) {
    throw new Error(`fixture source URL must be official Mermaid docs: ${fixture.file}`);
  }
  if (!fixture.rootType) {
    throw new Error(`fixture root type is required: ${fixture.file}`);
  }
  if (!validStatuses.has(fixture.expectedParserStatus)) {
    throw new Error(`invalid parser status for ${fixture.file}`);
  }
  if (!validStatuses.has(fixture.expectedRenderStatus)) {
    throw new Error(`invalid render status for ${fixture.file}`);
  }
  if (!fixture.source.includes(fixture.rootType)) {
    throw new Error(`fixture source must include root type ${fixture.rootType}: ${fixture.file}`);
  }
}

async function readExisting(filePath) {
  try {
    return await readFile(filePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

function relative(filePath) {
  return path.relative(root, filePath);
}
