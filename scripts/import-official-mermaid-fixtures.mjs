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
  {
    file: "class.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/classDiagram.html",
    rootType: "class",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid class examples
%%{ init: { 'theme': 'base' } }%%
classDiagram
direction LR
class Animal {
+String name
+eat() void
}
Animal <|-- Dog : inherits
Dog : +bark() void
`,
  },
  {
    file: "er.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/entityRelationshipDiagram.html",
    rootType: "er",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid ER examples
%%{ init: { 'theme': 'base' } }%%
erDiagram
CUSTOMER {
  string name PK
  string email UK
}
ORDER {
  int id PK
  string status
}
CUSTOMER ||--o{ ORDER : places
`,
  },
  {
    file: "gantt.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/gantt.html",
    rootType: "gantt",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid Gantt examples
%%{ init: { 'theme': 'base' } }%%
gantt
title Release Plan
dateFormat YYYY-MM-DD
axisFormat %m-%d
section Build
Design API :done, api, 2026-01-01, 3d
Implement core :active, core, after api, 5d
`,
  },
  {
    file: "pie.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/pie.html",
    rootType: "pie",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid pie examples
%%{ init: { 'theme': 'base' } }%%
pie showData title Build Time
"Compile" : 70.50
"Test" : 24.25
"Package" : 5.25
`,
  },
  {
    file: "mindmap.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/mindmap.html",
    rootType: "mindmap",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid mindmap examples
%%{ init: { 'theme': 'base' } }%%
mindmap
  Root
    ::icon(fa fa-code)
    [Parser]:::core
      AST
      Layout
    )Renderer(:::ui
      SVG
      GIF
`,
  },
  {
    file: "journey.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/userJourney.html",
    rootType: "journey",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid journey examples
%%{ init: { 'theme': 'base' } }%%
journey
title Checkout
section Browse
Visit homepage: 5: Customer
Search product: 4: Customer, Search
section Purchase
Enter address: 2: Customer
Payment: 3: Customer, Gateway
`,
  },
  {
    file: "gitgraph.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/gitgraph.html",
    rootType: "gitgraph",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid GitGraph examples
%%{ init: { 'theme': 'base' } }%%
gitGraph TB:
commit id: "base"
branch feature order: 2
commit id: "feat" type: HIGHLIGHT tag: "v1"
checkout main
commit id: "main2"
merge feature id: "merge" tag: "release"
cherry-pick id: "feat" parent: "base"
`,
  },
  {
    file: "timeline.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/timeline.html",
    rootType: "timeline",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid timeline examples
%%{ init: { 'theme': 'base' } }%%
timeline
title Release Train
section Alpha
2024 Q1 : Design : Prototype
        : Validate
section Beta
2024 Q2 : Build
2024 Q3 : Ship : Measure
`,
  },
  {
    file: "requirement.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/requirementDiagram.html",
    rootType: "requirement",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid requirement examples
%%{ init: { 'theme': 'base' } }%%
requirementDiagram
direction LR
functionalRequirement req_login {
  id: 1.1
  text: login accepts valid users
  risk: low
  verifyMethod: inspection
}
performanceRequirement req_latency {
  id: 1.2
  text: response under 250ms
  risk: medium
  verifymethod: demonstration
}
element api {
  type: service
  docRef: docs/api.md
}
req_login - contains -> req_latency
req_latency <- verifies - api
`,
  },
  {
    file: "c4.mmd",
    sourceUrl: "https://mermaid.js.org/syntax/c4.html",
    rootType: "c4",
    expectedParserStatus: "pass",
    expectedRenderStatus: "pass",
    source: `%% generated from official Mermaid C4 examples
%%{ init: { 'theme': 'base' } }%%
C4Container
title Container View
System_Boundary(system, "Internet Banking System") {
  Container(web_app, "Web Application", "Java/Spring MVC", "Delivers static content")
  ContainerDb(database, "Database", "Relational Database", "Stores account data")
  ContainerQueue(queue, "Queue", "RabbitMQ", "Async work")
}
Person(customer, "Customer", "Uses online banking")
Rel(customer, web_app, "Uses", "HTTPS")
Rel(web_app, database, "DB")
Rel(web_app, queue, "Publishes messages", "AMQP")
UpdateElementStyle(web_app, $bgColor:"#1168bd")
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
  if (!fixture.source.toLowerCase().includes(fixture.rootType.toLowerCase())) {
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
