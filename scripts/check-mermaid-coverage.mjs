import { readFile } from "node:fs/promises";

const syntaxDocsApiUrl =
  process.env.MERMAID_DOCS_API_URL ??
  "https://api.github.com/repos/mermaid-js/mermaid/contents/packages/mermaid/src/docs/syntax?ref=develop";

const expectedSyntaxDocs = new Map([
  ["architecture.md", "Architecture"],
  ["block.md", "Block Diagram"],
  ["c4.md", "C4 Diagram"],
  ["classDiagram.md", "Class Diagram"],
  ["cynefin.md", "Cynefin Framework Diagram"],
  ["entityRelationshipDiagram.md", "Entity Relationship Diagram"],
  ["eventmodeling.md", "Event Modeling"],
  ["flowchart.md", "Flowchart"],
  ["gantt.md", "Gantt"],
  ["gitgraph.md", "GitGraph Diagram"],
  ["ishikawa.md", "Ishikawa"],
  ["kanban.md", "Kanban"],
  ["mindmap.md", "Mindmaps"],
  ["packet.md", "Packet"],
  ["pie.md", "Pie Chart"],
  ["quadrantChart.md", "Quadrant Chart"],
  ["radar.md", "Radar"],
  ["railroad.md", "Railroad Diagram"],
  ["requirementDiagram.md", "Requirement Diagram"],
  ["sankey.md", "Sankey"],
  ["sequenceDiagram.md", "Sequence Diagram"],
  ["stateDiagram.md", "State Diagram"],
  ["swimlanes.md", "Swimlanes Diagram"],
  ["timeline.md", "Timeline"],
  ["treeView.md", "TreeView"],
  ["treemap.md", "Treemap"],
  ["userJourney.md", "User Journey"],
  ["venn.md", "Venn"],
  ["wardley.md", "Wardley"],
  ["xyChart.md", "XY Chart"],
  ["zenuml.md", "ZenUML"],
]);

const ignoredDocs = new Set(["examples.md"]);

const coverageText = await readFile(new URL("../COVERAGE.md", import.meta.url), "utf8");
const coverageRows = parseCoverageRows(coverageText);
const upstreamDocs = await fetchSyntaxDocs();

const upstreamNames = upstreamDocs
  .filter((entry) => entry.type === "file" && entry.name.endsWith(".md"))
  .map((entry) => entry.name)
  .filter((name) => !ignoredDocs.has(name))
  .sort();

const unmappedDocs = upstreamNames.filter((name) => !expectedSyntaxDocs.has(name));
const missingCoverageRows = upstreamNames
  .filter((name) => expectedSyntaxDocs.has(name))
  .map((name) => expectedSyntaxDocs.get(name))
  .filter((type) => !coverageRows.has(type));
const staleCoverageRows = [...coverageRows.keys()]
  .filter((type) => ![...expectedSyntaxDocs.values()].includes(type))
  .sort();

if (unmappedDocs.length || missingCoverageRows.length || staleCoverageRows.length) {
  const failures = [];
  if (unmappedDocs.length) {
    failures.push(`Unmapped Mermaid syntax docs:\n${formatList(unmappedDocs)}`);
  }
  if (missingCoverageRows.length) {
    failures.push(`Missing COVERAGE.md rows:\n${formatList(missingCoverageRows)}`);
  }
  if (staleCoverageRows.length) {
    failures.push(`COVERAGE.md rows without upstream syntax docs:\n${formatList(staleCoverageRows)}`);
  }
  console.error(`Mermaid coverage drift detected.\nSource: ${syntaxDocsApiUrl}\n\n${failures.join("\n\n")}`);
  process.exit(1);
}

console.log(`Mermaid docs syntax coverage is current (${upstreamNames.length} roots checked).`);

async function fetchSyntaxDocs() {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "kumeyuri-compat-check",
  };
  const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  const response = await fetch(syntaxDocsApiUrl, { headers });
  if (!response.ok) {
    throw new Error(`failed to fetch Mermaid syntax docs: ${response.status} ${response.statusText}`);
  }
  const json = await response.json();
  if (!Array.isArray(json)) {
    throw new Error("Mermaid syntax docs response was not a directory listing");
  }
  return json;
}

function parseCoverageRows(markdown) {
  const rows = new Map();
  let inMatrix = false;
  for (const line of markdown.split("\n")) {
    if (line === "## Matrix") {
      inMatrix = true;
      continue;
    }
    if (!inMatrix || !line.startsWith("|")) {
      continue;
    }
    const cells = splitMarkdownRow(line);
    if (cells[0] === "Mermaid diagram type" || cells[0] === "---") {
      continue;
    }
    rows.set(cells[0], cells);
  }
  return rows;
}

function splitMarkdownRow(line) {
  const cells = [];
  let cell = "";
  let inCode = false;
  const body = stripOuterPipes(line.trim());
  for (let index = 0; index < body.length; index += 1) {
    const char = body[index];
    if (char === "`") {
      inCode = !inCode;
    }
    if (char === "|" && !inCode && body[index - 1] !== "\\") {
      cells.push(cell.trim());
      cell = "";
    } else {
      cell += char;
    }
  }
  cells.push(cell.trim());
  return cells;
}

function stripOuterPipes(value) {
  const start = value.startsWith("|") ? 1 : 0;
  const end = value.endsWith("|") ? value.length - 1 : value.length;
  return value.slice(start, end);
}

function formatList(items) {
  return items.map((item) => `- ${item}`).join("\n");
}
