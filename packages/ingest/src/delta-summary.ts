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
  license_changes: SourceLicenseChange[];
  quality_samples: QualitySample[];
  removed: CanonicalEntry[];
  source: string;
}

export interface QualitySample {
  domains: string[];
  expansion: string;
  source_count: number;
  term: string;
}

export interface SourceLicenseChange {
  current_entry: string;
  current_license: string;
  previous_entry: string;
  previous_license: string;
  title: string;
  url: string;
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
  const licenseChanges = sourceLicenseChanges(current.entries, previous?.entries ?? []);
  const qualitySamples = qualitySampleEntries(
    current.entries,
    `${current.source}:${current.generated_at}`
  );

  return {
    added,
    changed,
    license_changes: licenseChanges,
    quality_samples: qualitySamples,
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
  const licenseChangeRows = summary.license_changes.map(
    (change) =>
      `| ${escapeCell(change.url)} | ${escapeCell(change.previous_license)} | ${escapeCell(
        change.current_license
      )} | ${escapeCell(change.current_entry)} |`
  );
  const qualitySampleRows = summary.quality_samples.map(
    (sample) =>
      `| ${escapeCell(sample.term)} | ${escapeCell(sample.expansion)} | ${escapeCell(
        sample.domains.join(", ")
      )} | ${sample.source_count} |`
  );

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
    "",
    "## Source license changes",
    "",
    summary.license_changes.length > 0
      ? "Automatic import is blocked until these license changes are reviewed."
      : "No source license changes detected.",
    "",
    "| Source URL | Previous license | Current license | Entry |",
    "| --- | --- | --- | --- |",
    ...(licenseChangeRows.length > 0 ? licenseChangeRows : ["| none |  |  |  |"]),
    "",
    "## Quality review sample",
    "",
    "Review these deterministic-random entries before merging the refresh PR.",
    "",
    "| Term | Expansion | Domains | Sources |",
    "| --- | --- | --- | ---: |",
    ...(qualitySampleRows.length > 0 ? qualitySampleRows : ["| none |  |  | 0 |"]),
    ""
  ].join("\n");
}

export function assertNoSourceLicenseChanges(summary: DeltaSummary): void {
  if (summary.license_changes.length > 0) {
    throw new Error("source license change detected; review before import");
  }
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

function sourceLicenseChanges(
  currentEntries: CanonicalEntry[],
  previousEntries: CanonicalEntry[]
): SourceLicenseChange[] {
  const previousByUrl = new Map<
    string,
    { entry: CanonicalEntry; license: string; title: string }
  >();

  for (const entry of previousEntries) {
    for (const source of entry.sources) {
      previousByUrl.set(source.url, {
        entry,
        license: source.license,
        title: source.title
      });
    }
  }

  const changes: SourceLicenseChange[] = [];
  for (const entry of currentEntries) {
    for (const source of entry.sources) {
      const previous = previousByUrl.get(source.url);
      if (!previous || previous.license === source.license) continue;
      changes.push({
        current_entry: entry.dedup_key,
        current_license: source.license,
        previous_entry: previous.entry.dedup_key,
        previous_license: previous.license,
        title: source.title || previous.title,
        url: source.url
      });
    }
  }

  return changes.sort((left, right) => left.url.localeCompare(right.url));
}

function qualitySampleEntries(entries: CanonicalEntry[], seed: string, limit = 5): QualitySample[] {
  return [...entries]
    .sort(
      (left, right) =>
        sampleScore(seed, left.dedup_key) - sampleScore(seed, right.dedup_key) ||
        left.dedup_key.localeCompare(right.dedup_key)
    )
    .slice(0, limit)
    .map((entry) => ({
      domains: entry.domains,
      expansion: entry.expansions[0] ?? "",
      source_count: entry.sources.length,
      term: entry.term
    }));
}

function sampleScore(seed: string, value: string): number {
  let hash = 2166136261;
  for (const char of `${seed}:${value}`) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function sampleRow(change: string, entry: CanonicalEntry): [string, string, string] {
  return [change, entry.term, entry.expansions[0] ?? ""];
}

function escapeCell(value: string): string {
  return value.replaceAll("|", "\\|").replace(/\s+/g, " ").trim();
}

const [, , inputPath, outputPath] = process.argv;

if (isDirectDeltaSummaryCli() && inputPath && outputPath) {
  const resolvedInputPath = resolveRepoPath(inputPath);
  const resolvedOutputPath = resolveRepoPath(outputPath);
  const current = JSON.parse(await readFile(resolvedInputPath, "utf8")) as DeltaFile;
  const previous = await findPreviousDelta(resolvedInputPath, current.source);
  const summary = summarizeDelta(current, previous);
  if (process.env.WAT_LICENSE_CHANGE_REVIEWED !== "1") {
    assertNoSourceLicenseChanges(summary);
  }
  const markdown = renderDeltaSummary(summary, inputPath);
  await mkdir(dirname(resolvedOutputPath), { recursive: true });
  await writeFile(resolvedOutputPath, markdown);
} else if (isDirectDeltaSummaryCli()) {
  throw new Error("usage: tsx src/delta-summary.ts <delta-json> <output-md>");
}

function isDirectDeltaSummaryCli(): boolean {
  return process.argv[1]?.endsWith("delta-summary.ts") === true;
}

function resolveRepoPath(path: string): string {
  return isAbsolute(path) ? path : join(rootDir, path);
}
