import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { devTeamEntries } from "./team-fixtures.js";
import type {
  AuthContext,
  ConfidenceTier,
  EntryLayer,
  WatAlternativesResult,
  WatEntry,
  WatResult
} from "./types.js";

const confidenceRank: Record<ConfidenceTier, number> = {
  T1: 1,
  T2: 2,
  T3: 3,
  T4: 4
};

const layerRank: Record<EntryLayer, number> = {
  personal: 0,
  team: 1,
  public: 2
};

const here = dirname(fileURLToPath(import.meta.url));
const defaultCorpusPaths = [
  "packages/ingest/seeds/manual.json",
  "data/deltas/2026-06-23/contemporaries-seed.json"
];

async function readCorpusJson(relativePath: string): Promise<string> {
  const candidates = [
    join(process.cwd(), relativePath),
    join(process.cwd(), "../../", relativePath),
    join(here, "../../../", relativePath)
  ];

  for (const candidate of candidates) {
    try {
      return await readFile(candidate, "utf8");
    } catch {
      continue;
    }
  }

  throw new Error(`corpus file not found: ${relativePath}`);
}

async function readCorpusFiles(): Promise<Array<{ entries?: WatEntry[] }>> {
  if (process.env.WAT_SEED_PATH) {
    return [
      JSON.parse(await readFile(process.env.WAT_SEED_PATH, "utf8")) as { entries?: WatEntry[] }
    ];
  }

  return Promise.all(
    defaultCorpusPaths.map(
      async (relativePath) =>
        JSON.parse(await readCorpusJson(relativePath)) as { entries?: WatEntry[] }
    )
  );
}

async function publicEntries(): Promise<WatEntry[]> {
  const files = await readCorpusFiles();
  return overlaySeedContemporaries(
    files.flatMap((file) => file.entries ?? []).filter((entry) => entry.layer === "public")
  );
}

function overlaySeedContemporaries(entries: WatEntry[]): WatEntry[] {
  const output: WatEntry[] = [];
  const byTerm = new Map<string, WatEntry>();

  for (const entry of entries) {
    const key = entry.term_normalized || entry.term.toLowerCase();
    const existing = byTerm.get(key);
    if (existing && entry.id.startsWith("contemporaries-seed-")) {
      existing.contemporaries = uniqueStrings([
        ...existing.contemporaries,
        ...entry.contemporaries
      ]);
      existing.aliases = uniqueStrings([...existing.aliases, ...entry.aliases]);
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

function toResult(entry: WatEntry, score: number): WatResult {
  return {
    citations: entry.sources,
    confidence_tier: entry.confidence_tier,
    contemporaries: entry.contemporaries,
    domains: entry.domains,
    entry_id: entry.id,
    expansion: entry.expansions[0] ?? entry.term,
    layer: entry.layer,
    meaning: entry.meaning_short,
    score,
    term: entry.term
  };
}

function scoreEntry(query: string, context: string | undefined, entry: WatEntry): WatResult | null {
  const normalized = query.toLowerCase().trim();
  const contextText = context?.toLowerCase() ?? "";
  const searchable = [
    entry.term,
    entry.term_normalized,
    ...entry.expansions,
    ...entry.contemporaries,
    ...entry.domains,
    ...entry.aliases,
    entry.meaning_short
  ]
    .join(" ")
    .toLowerCase();

  if (!searchable.includes(normalized)) {
    return null;
  }

  const exact = entry.term_normalized === normalized ? 1 : 0;
  const expansion = entry.expansions.some((value) => value.toLowerCase().includes(normalized))
    ? 0.8
    : 0;
  const contemporary = entry.contemporaries.some((value) =>
    value.toLowerCase().includes(normalized)
  )
    ? 0.35
    : 0;
  const domain = entry.domains.some((value) => value.toLowerCase().includes(normalized)) ? 0.4 : 0;
  const body = entry.meaning_short.toLowerCase().includes(normalized) ? 0.25 : 0;
  const contextBoost = entry.domains.some((value) => contextText.includes(value.toLowerCase()))
    ? 0.3
    : 0;

  return toResult(entry, exact + expansion + contemporary + domain + body + contextBoost);
}

async function visibleEntries(auth: AuthContext): Promise<WatEntry[]> {
  return [...devTeamEntries, ...(await publicEntries())].filter((entry) => {
    if (entry.layer === "team") {
      return entry.team_id === auth.team_id;
    }

    return true;
  });
}

export async function lookupEntries(input: {
  auth: AuthContext;
  context?: string;
  limit?: number;
  min_confidence?: ConfidenceTier;
  term: string;
}): Promise<WatResult[]> {
  const minConfidence = input.min_confidence ?? "T4";
  const entries = (await visibleEntries(input.auth)).filter((entry) => {
    if (confidenceRank[entry.confidence_tier] > confidenceRank[minConfidence]) {
      return false;
    }

    return true;
  });

  return entries
    .map((entry) => scoreEntry(input.term, input.context, entry))
    .filter((result): result is WatResult => result != null)
    .sort(
      (left, right) =>
        right.score - left.score ||
        layerRank[left.layer] - layerRank[right.layer] ||
        left.entry_id.localeCompare(right.entry_id)
    )
    .slice(0, Number.isFinite(input.limit) && input.limit && input.limit > 0 ? input.limit : 5);
}

function normalizeLookupKey(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function findEntry(term: string, entries: WatEntry[]): WatEntry | null {
  const key = normalizeLookupKey(term);
  const matches = entries.filter(
    (entry) =>
      entry.id === term ||
      normalizeLookupKey(entry.term) === key ||
      normalizeLookupKey(entry.term_normalized) === key ||
      entry.aliases.some((alias) => normalizeLookupKey(alias) === key)
  );

  return matches.find((entry) => entry.contemporaries.length > 0) ?? matches[0] ?? null;
}

export async function listAlternatives(input: {
  auth: AuthContext;
  term: string;
}): Promise<WatAlternativesResult> {
  const entries = await visibleEntries(input.auth);
  const entry = findEntry(input.term, entries);
  if (!entry) {
    return { alternatives: [], entry: null, unresolved_terms: [] };
  }

  const alternatives: WatResult[] = [];
  const unresolvedTerms: string[] = [];

  for (const contemporary of entry.contemporaries) {
    const alternative = findEntry(contemporary, entries);
    if (alternative) {
      alternatives.push(toResult(alternative, 1));
    } else {
      unresolvedTerms.push(contemporary);
    }
  }

  return {
    alternatives,
    entry: toResult(entry, 1),
    unresolved_terms: unresolvedTerms
  };
}

export function listTeamEntries(input: {
  auth: AuthContext;
  cursor?: number;
  domain?: string;
  limit?: number;
}): { entries: WatResult[]; next_cursor: number | null } {
  const limit = Number.isFinite(input.limit) && input.limit && input.limit > 0 ? input.limit : 25;
  const cursor =
    Number.isFinite(input.cursor) && input.cursor && input.cursor > 0 ? input.cursor : 0;
  const domain = input.domain?.toLowerCase();
  const entries = devTeamEntries.filter((entry) => {
    if (entry.team_id !== input.auth.team_id) {
      return false;
    }

    return !domain || entry.domains.includes(domain);
  });
  const page = entries.slice(cursor, cursor + limit).map((entry) => toResult(entry, 1));
  const nextCursor = cursor + limit < entries.length ? cursor + limit : null;

  return { entries: page, next_cursor: nextCursor };
}

export function resultText(results: WatResult[]): string {
  if (results.length === 0) {
    return "No wat matches.";
  }

  return results
    .map((result) => {
      const citations = result.citations.map((source) => source.url).join(", ");
      const alternatives = result.contemporaries.length
        ? `\nAlternatives: ${result.contemporaries.join(", ")}`
        : "";
      return `${result.term}: ${result.expansion} (${result.confidence_tier}, ${result.layer})\n${result.meaning}${alternatives}\nSources: ${citations}`;
    })
    .join("\n\n");
}
