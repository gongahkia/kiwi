import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { searchHybrid, type HybridSearchCandidate } from "./hybrid.js";

interface AcronymFixtureEntry {
  acronym: string;
  expected_answer: string;
  query: string;
  source_license: string;
  source_url: string;
}

interface DeltaEntry {
  __file?: string;
  __index?: number;
  aliases?: string[];
  contemporaries?: string[];
  dedup_key?: string;
  domains?: string[];
  expansions?: string[];
  id?: string;
  meaning?: string;
  meaning_short?: string;
  sources?: Array<{ license?: string; url?: string }>;
  term?: string;
}

export interface MixedBenchmarkCase {
  candidate: HybridSearchCandidate;
  expected_id: string;
  kind: "acronym" | "concept" | "system";
  query: string;
  source_license: string;
  source_url: string;
}

export interface MixedBenchmarkReport {
  corpus: string;
  engine: string;
  total_cases: number;
  top_1_hit_rate: number;
  top_1_hits: number;
  top_5_hit_rate: number;
  top_5_hits: number;
}

const acronymCount = 500;
const conceptCount = 300;
const systemCount = 200;
const packageRoot = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));

export function buildMixedBenchmark(): MixedBenchmarkCase[] {
  const acronymRows = readAcronymRows();
  const usedQueries = new Set(acronymRows.map((row) => normalizeLookup(row.query)));
  const usedIds = new Set(acronymRows.map((row) => row.expected_id));
  const entries = readDeltaEntries();
  const conceptRows = addRows({
    entries: conceptEntries(entries),
    kind: "concept",
    limit: conceptCount,
    usedIds,
    usedQueries
  });
  const systemRows = addRows({
    entries: systemEntries(entries),
    kind: "system",
    limit: systemCount,
    usedIds,
    usedQueries
  });

  return [...acronymRows, ...conceptRows, ...systemRows];
}

export function runMixedBenchmark(cases = buildMixedBenchmark()): MixedBenchmarkReport {
  const candidates = cases.map((row) => row.candidate);
  let top1Hits = 0;
  let top5Hits = 0;

  for (const row of cases) {
    const matches = searchHybrid(row.query, candidates, { limit: 5 });
    if (matches[0]?.candidate.id === row.expected_id) top1Hits += 1;
    if (matches.some((match) => match.candidate.id === row.expected_id)) top5Hits += 1;
  }

  return {
    corpus: "mixed-search-benchmark",
    engine: "searchHybrid",
    total_cases: cases.length,
    top_1_hits: top1Hits,
    top_1_hit_rate: top1Hits / cases.length,
    top_5_hits: top5Hits,
    top_5_hit_rate: top5Hits / cases.length
  };
}

function readAcronymRows(): MixedBenchmarkCase[] {
  const entries = JSON.parse(
    readFileSync(join(packageRoot, "fixtures", "dev-tooling-acronyms.json"), "utf8")
  ) as AcronymFixtureEntry[];

  return entries.slice(0, acronymCount).map((entry, index) => ({
    candidate: {
      expansions: [entry.expected_answer],
      id: `acronym-${index}`,
      term: entry.acronym
    },
    expected_id: `acronym-${index}`,
    kind: "acronym",
    query: entry.query,
    source_license: entry.source_license,
    source_url: entry.source_url
  }));
}

function addRows({
  entries,
  kind,
  limit,
  usedIds,
  usedQueries
}: {
  entries: DeltaEntry[];
  kind: "concept" | "system";
  limit: number;
  usedIds: Set<string>;
  usedQueries: Set<string>;
}): MixedBenchmarkCase[] {
  const rows: MixedBenchmarkCase[] = [];

  for (const entry of entries) {
    const source = entry.sources?.find((item) => item.license && item.url);
    const expansion = entry.expansions?.[0] ?? entry.term;
    if (!source?.license || !source.url || !validText(entry.term) || !validText(expansion)) {
      continue;
    }

    const query = entry.term;
    const normalizedQuery = normalizeLookup(query);
    if (!normalizedQuery || usedQueries.has(normalizedQuery)) continue;

    const candidate = candidateFromEntry(entry, kind, usedIds);
    if (!candidate) continue;

    rows.push({
      candidate,
      expected_id: candidate.id,
      kind,
      query,
      source_license: source.license,
      source_url: source.url
    });
    usedQueries.add(normalizedQuery);
    usedIds.add(candidate.id);
    if (rows.length === limit) break;
  }

  return rows;
}

function candidateFromEntry(
  entry: DeltaEntry,
  kind: "concept" | "system",
  usedIds: Set<string>
): HybridSearchCandidate | null {
  const id = `${kind}-${slug(entry.dedup_key ?? entry.id ?? `${entry.term}-${entry.__index}`)}`;
  if (usedIds.has(id) || !entry.term) return null;

  return {
    aliases: entry.aliases ?? [],
    contemporaries: entry.contemporaries ?? [],
    domains: entry.domains ?? [],
    expansions: entry.expansions ?? [entry.term],
    id,
    meaning_short: entry.meaning_short ?? entry.meaning ?? "",
    term: entry.term
  };
}

function conceptEntries(entries: DeltaEntry[]): DeltaEntry[] {
  return entries
    .filter((entry) => {
      const domains = lowerDomains(entry);
      if (
        domains.some((domain) =>
          [
            "aws",
            "azure",
            "gcp",
            "google cloud",
            "service names",
            "wikipedia",
            "acronyms"
          ].includes(domain)
        )
      ) {
        return false;
      }
      if (!entry.term || /^[A-Z0-9.+-]{2,8}$/.test(entry.term)) return false;
      return [
        "web platform",
        "mdn",
        "w3c",
        "postgresql",
        "database",
        "cloud native",
        "linux foundation"
      ].some((domain) => domains.includes(domain));
    })
    .sort(compareTerms);
}

function systemEntries(entries: DeltaEntry[]): DeltaEntry[] {
  return entries
    .filter((entry) => {
      const domains = lowerDomains(entry);
      return ["aws", "azure", "gcp", "google cloud", "service names"].some((domain) =>
        domains.includes(domain)
      );
    })
    .filter((entry) => !/^[A-Z0-9.+-]{2,8}$/.test(entry.term ?? ""))
    .sort(compareTerms);
}

function readDeltaEntries(): DeltaEntry[] {
  const entries: DeltaEntry[] = [];
  for (const file of jsonFiles(join(repoRoot, "data", "deltas"))) {
    const parsed = JSON.parse(readFileSync(file, "utf8")) as { entries?: DeltaEntry[] };
    entries.push(
      ...(parsed.entries ?? []).map((entry, index) => ({ ...entry, __file: file, __index: index }))
    );
  }
  return entries;
}

function jsonFiles(dir: string): string[] {
  const files: string[] = [];
  for (const item of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, item.name);
    if (item.isDirectory()) {
      files.push(...jsonFiles(path));
    } else if (item.isFile() && item.name.endsWith(".json")) {
      files.push(path);
    }
  }
  return files.sort((left, right) => left.localeCompare(right));
}

function compareTerms(left: DeltaEntry, right: DeltaEntry): number {
  return (left.term ?? "").localeCompare(right.term ?? "");
}

function lowerDomains(entry: DeltaEntry): string[] {
  return (entry.domains ?? []).map((domain) => domain.toLowerCase());
}

function normalizeLookup(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function slug(value: unknown): string {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function validText(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[\x20-\x7e]+$/.test(value) &&
    /[A-Za-z]/.test(value) &&
    value.length >= 3 &&
    value.length <= 64
  );
}
