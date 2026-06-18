import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const watchedFiles = [
  "crates/kumeyuri-core/src/ast.rs",
  "crates/kumeyuri-core/src/parser.rs",
  "crates/kumeyuri-core/src/frame.rs",
  "crates/kumeyuri-core/src/animator.rs",
];

const base = resolveBaseRevision();
const head = resolveHeadRevision();

if (!base) {
  console.log("No coverage gate base revision; skipping snapshot-count delta check.");
  process.exit(0);
}

const dispatchDiff = git(["diff", "--unified=0", base, head, "--", ...watchedFiles]);
const dispatchChanges = dispatchChangeEvidence(dispatchDiff);

if (!dispatchChanges.length) {
  console.log("No DiagramKind, parser root dispatch, or render dispatch changes detected.");
  process.exit(0);
}

const oldCoverage = git(["show", `${base}:COVERAGE.md`]);
const newCoverage = coverageAtRevision(head);
const snapshotDeltas = snapshotCountDeltas(oldCoverage, newCoverage);

if (!snapshotDeltas.length) {
  console.error(
    [
      "Coverage snapshot-count gate failed.",
      "",
      "Dispatch surface changed:",
      ...dispatchChanges.map((change) => `- ${change}`),
      "",
      "Update the Snapshot count column in COVERAGE.md when changing DiagramKind, parser root dispatch, or render dispatch.",
    ].join("\n"),
  );
  process.exit(1);
}

console.log("Coverage snapshot-count gate passed.");
for (const delta of snapshotDeltas) {
  console.log(`- ${delta}`);
}

function resolveBaseRevision() {
  const explicit = process.env.COVERAGE_GATE_BASE;
  if (explicit && !allZeros(explicit) && revExists(explicit)) {
    return explicit;
  }
  const githubBase = process.env.GITHUB_BASE_REF;
  if (githubBase) {
    const mergeBase = git(["merge-base", "HEAD", `origin/${githubBase}`], { allowFailure: true });
    if (mergeBase.trim()) {
      return mergeBase.trim();
    }
  }
  if (revExists("HEAD~1")) {
    return "HEAD~1";
  }
  return null;
}

function resolveHeadRevision() {
  const explicit = process.env.COVERAGE_GATE_HEAD;
  if (explicit && !allZeros(explicit) && revExists(explicit)) {
    return explicit;
  }
  return "HEAD";
}

function dispatchChangeEvidence(diff) {
  const changes = [];
  let file = "";
  for (const line of diff.split("\n")) {
    if (line.startsWith("+++ b/")) {
      file = line.slice("+++ b/".length);
      continue;
    }
    if (!file || line.startsWith("+++") || line.startsWith("---")) {
      continue;
    }
    if (!line.startsWith("+") && !line.startsWith("-")) {
      continue;
    }
    const text = line.slice(1);
    if (isDispatchChange(file, text)) {
      changes.push(`${file}: ${text.trim()}`);
    }
  }
  return changes;
}

function isDispatchChange(file, text) {
  if (file.endsWith("/ast.rs")) {
    return text.includes("DiagramKind") || isAstVariantLine(text);
  }
  if (file.endsWith("/parser.rs")) {
    return text.includes("DiagramKind::") || isParserHeaderReference(text);
  }
  if (file.endsWith("/frame.rs")) {
    return text.includes("DiagramKind::") || text.includes("render_diagram");
  }
  if (file.endsWith("/animator.rs")) {
    return text.includes("DiagramKind::") || text.includes("default_animation_mode");
  }
  return false;
}

function snapshotCountDeltas(oldCoverage, newCoverage) {
  const oldRows = parseCoverageRows(oldCoverage);
  const newRows = parseCoverageRows(newCoverage);
  const rowNames = new Set([...oldRows.keys(), ...newRows.keys()]);
  const deltas = [];
  for (const name of [...rowNames].sort()) {
    const oldCount = oldRows.get(name)?.[8] ?? "<missing>";
    const newCount = newRows.get(name)?.[8] ?? "<missing>";
    if (oldCount !== newCount) {
      deltas.push(`${name}: ${oldCount} -> ${newCount}`);
    }
  }
  return deltas;
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

function revExists(revision) {
  return spawnSync("git", ["rev-parse", "--verify", `${revision}^{commit}`], {
    encoding: "utf8",
  }).status === 0;
}

function allZeros(value) {
  return value.length > 0 && Array.from(value).every((char) => char === "0");
}

function isAstVariantLine(text) {
  const trimmed = text.trimStart();
  const box = "(Box<";
  const boxIndex = trimmed.indexOf(box);
  if (boxIndex <= 0 || !trimmed.endsWith(">),")) {
    return false;
  }
  const variant = trimmed.slice(0, boxIndex);
  return isRustUpperIdentifier(variant) && trimmed.slice(boxIndex + box.length, -3).endsWith("Ast");
}

function isParserHeaderReference(text) {
  const marker = "parse_";
  let cursor = text.indexOf(marker);
  while (cursor !== -1) {
    const end = readRustIdentifierEnd(text, cursor);
    if (text.slice(cursor, end).endsWith("_header")) {
      return true;
    }
    cursor = text.indexOf(marker, cursor + marker.length);
  }
  return false;
}

function readRustIdentifierEnd(text, start) {
  let end = start;
  while (end < text.length && isRustIdentifierChar(text[end])) {
    end += 1;
  }
  return end;
}

function isRustUpperIdentifier(value) {
  return (
    value.length > 0 &&
    value[0] >= "A" &&
    value[0] <= "Z" &&
    Array.from(value).every(isRustIdentifierChar)
  );
}

function isRustIdentifierChar(char) {
  return (char >= "A" && char <= "Z") || (char >= "a" && char <= "z") || (char >= "0" && char <= "9") || char === "_";
}

function stripOuterPipes(value) {
  let start = value.startsWith("|") ? 1 : 0;
  let end = value.endsWith("|") ? value.length - 1 : value.length;
  return value.slice(start, end);
}

function coverageAtRevision(revision) {
  if (revision === "HEAD") {
    return readFileSync(new URL("../COVERAGE.md", import.meta.url), "utf8");
  }
  return git(["show", `${revision}:COVERAGE.md`]);
}

function git(args, options = {}) {
  const result = spawnSync("git", args, { encoding: "utf8" });
  if (result.status !== 0 && !options.allowFailure) {
    throw new Error(result.stderr.trim() || `git ${args.join(" ")} failed`);
  }
  return result.stdout;
}
