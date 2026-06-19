import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

import type { CanonicalEntry } from "./transform.js";

export interface DeltaFile {
  entries: CanonicalEntry[];
  generated_at: string;
  source: string;
}

export interface DeltaSummary {
  added: CanonicalEntry[];
  changed: CanonicalEntry[];
  removed: CanonicalEntry[];
  source: string;
}

const rootDir = fileURLToPath(new URL("../../..", import.meta.url));

export function summarizeDelta(current: DeltaFile, previous: DeltaFile | null): DeltaSummary {
  const previousEntries = new Map(
    (previous?.entries ?? []).map((entry) => [entryKey(entry), entry])
  );
  const currentEntries = new Map(current.entries.map((entry) => [entryKey(entry), entry]));
  const added = current.entries.filter((entry) => !previousEntries.has(entryKey(entry)));
  const changed = current.entries.filter((entry) => {
    const previousEntry = previousEntries.get(entryKey(entry));
    return previousEntry ? JSON.stringify(previousEntry) !== JSON.stringify(entry) : false;
  });
  const removed = (previous?.entries ?? []).filter((entry) => !currentEntries.has(entryKey(entry)));

  return {
    added,
    changed,
    removed,
    source: current.source
  };
}

export function renderDeltaSummary(summary: DeltaSummary, deltaPath: string): string {
  const rows = [
    ["Added", summary.added.length],
    ["Changed", summary.changed.length],
    ["Removed", summary.removed.length]
  ];
  const samples = [
    ...summary.added.slice(0, 5).map((entry) => sampleRow("added", entry)),
    ...summary.changed.slice(0, 5).map((entry) => sampleRow("changed", entry)),
    ...summary.removed.slice(0, 5).map((entry) => sampleRow("removed", entry))
  ];
  const sampleRows: [string, string, string][] = samples.length > 0 ? samples : [["none", "", ""]];

  return [
    `# Corpus refresh: ${summary.source}`,
    "",
    `Delta: \`${deltaPath}\``,
    "",
    "| Change | Count |",
    "| --- | ---: |",
    ...rows.map(([label, count]) => `| ${label} | ${count} |`),
    "",
    "| Sample | Term | Expansion |",
    "| --- | --- | --- |",
    ...sampleRows.map(
      ([change, term, expansion]) =>
        `| ${change} | ${escapeCell(term)} | ${escapeCell(expansion)} |`
    ),
    ""
  ].join("\n");
}

export async function findPreviousDelta(
  currentPath: string,
  source: string
): Promise<DeltaFile | null> {
  const deltasDir = join(rootDir, "data", "deltas");
  const dates = (await readdir(deltasDir, { withFileTypes: true }))
    .filter((item) => item.isDirectory())
    .map((item) => item.name)
    .sort((left, right) => right.localeCompare(left));

  for (const date of dates) {
    const candidate = join(deltasDir, date, `${source}.json`);
    if (candidate === currentPath) continue;
    try {
      return JSON.parse(await readFile(candidate, "utf8")) as DeltaFile;
    } catch {
      continue;
    }
  }

  return null;
}

function entryKey(entry: CanonicalEntry): string {
  return entry.dedup_key;
}

function sampleRow(change: string, entry: CanonicalEntry): [string, string, string] {
  return [change, entry.term, entry.expansions[0] ?? ""];
}

function escapeCell(value: string): string {
  return value.replaceAll("|", "\\|").replace(/\s+/g, " ").trim();
}

const [, , inputPath, outputPath] = process.argv;

if (inputPath && outputPath) {
  const resolvedInputPath = resolveRepoPath(inputPath);
  const resolvedOutputPath = resolveRepoPath(outputPath);
  const current = JSON.parse(await readFile(resolvedInputPath, "utf8")) as DeltaFile;
  const previous = await findPreviousDelta(resolvedInputPath, current.source);
  const markdown = renderDeltaSummary(summarizeDelta(current, previous), inputPath);
  await mkdir(dirname(resolvedOutputPath), { recursive: true });
  await writeFile(resolvedOutputPath, markdown);
} else if (process.argv[1]?.endsWith("delta-summary.ts")) {
  throw new Error("usage: tsx src/delta-summary.ts <delta-json> <output-md>");
}

function resolveRepoPath(path: string): string {
  return isAbsolute(path) ? path : join(rootDir, path);
}
