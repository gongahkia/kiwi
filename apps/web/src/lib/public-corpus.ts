import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { SearchEntry } from "@wat/search";

export interface PublicCorpusEntry extends SearchEntry {
  coiner: string | null;
  created_at: string;
  deprecated: boolean;
  deprecated_reason: string | null;
  examples: string[];
  license: string;
  meaning_long: string;
  related_terms: string[];
  team_id?: string | null;
  updated_at: string;
  year_coined: number | null;
}

interface CorpusFile {
  entries?: Partial<PublicCorpusEntry>[];
  generated_at?: string;
}

const corpusPaths = [
  "packages/ingest/seeds/manual.json",
  "data/deltas/2026-06-23/contemporaries-seed.json"
];

export async function getPublicCorpusEntries(): Promise<PublicCorpusEntry[]> {
  const files = await Promise.all(corpusPaths.map(readCorpusFile));
  const entries = files
    .flatMap((file) =>
      (file.entries ?? []).map((entry) => normalizeEntry(entry, file.generated_at))
    )
    .filter((entry) => entry.layer === "public");
  return overlaySeedContemporaries(entries);
}

async function readCorpusFile(relativePath: string): Promise<CorpusFile> {
  for (const candidate of [
    join(process.cwd(), relativePath),
    join(process.cwd(), "../../", relativePath)
  ]) {
    try {
      return JSON.parse(await readFile(candidate, "utf8")) as CorpusFile;
    } catch {
      continue;
    }
  }

  throw new Error(`corpus file not found: ${relativePath}`);
}

function normalizeEntry(entry: Partial<PublicCorpusEntry>, generatedAt = ""): PublicCorpusEntry {
  const term = entry.term ?? "";
  const expansions = entry.expansions?.length ? entry.expansions : [term];
  const meaning = entry.meaning_short ?? expansions[0] ?? term;
  const timestamp =
    generatedAt || entry.created_at || entry.updated_at || "1970-01-01T00:00:00.000Z";

  return {
    aliases: entry.aliases ?? [],
    coiner: entry.coiner ?? null,
    confidence_tier: entry.confidence_tier ?? "T3",
    contemporaries: entry.contemporaries ?? [],
    created_at: entry.created_at ?? timestamp,
    deprecated: entry.deprecated ?? false,
    deprecated_reason: entry.deprecated_reason ?? null,
    domains: entry.domains ?? [],
    examples: entry.examples ?? [],
    expansions,
    id: entry.id ?? term,
    layer: entry.layer ?? "public",
    license: entry.license ?? entry.sources?.[0]?.license ?? "MIT",
    meaning_long: entry.meaning_long ?? meaning,
    meaning_short: meaning,
    related_terms: entry.related_terms ?? [],
    sources: entry.sources ?? [],
    team_id: entry.team_id ?? null,
    term,
    term_normalized: entry.term_normalized ?? term.toLowerCase(),
    updated_at: entry.updated_at ?? timestamp,
    year_coined: entry.year_coined ?? null
  };
}

function overlaySeedContemporaries(entries: PublicCorpusEntry[]): PublicCorpusEntry[] {
  const output: PublicCorpusEntry[] = [];
  const byTerm = new Map<string, PublicCorpusEntry>();

  for (const entry of entries) {
    const key = entry.term_normalized || entry.term.toLowerCase();
    const existing = byTerm.get(key);
    if (existing && entry.id.startsWith("contemporaries-seed-")) {
      existing.contemporaries = uniqueStrings([
        ...existing.contemporaries,
        ...entry.contemporaries
      ]);
      existing.aliases = uniqueStrings([...existing.aliases, ...entry.aliases]);
      existing.related_terms = uniqueStrings([...existing.related_terms, ...entry.related_terms]);
      continue;
    }

    output.push(entry);
    byTerm.set(key, entry);
  }

  return output;
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const output: string[] = [];
  for (const value of values) {
    const normalized = value.trim();
    const key = normalized.toLowerCase();
    if (!normalized || seen.has(key)) continue;
    seen.add(key);
    output.push(normalized);
  }
  return output;
}
