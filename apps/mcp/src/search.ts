import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { devTeamEntries } from "./team-fixtures.js";
import type { AuthContext, ConfidenceTier, EntryLayer, WatEntry, WatResult } from "./types.js";

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

async function readSeedJson(): Promise<string> {
  const seedPath = process.env.WAT_SEED_PATH;
  const candidates = [
    seedPath,
    join(process.cwd(), "packages/ingest/seeds/manual.json"),
    join(process.cwd(), "../../packages/ingest/seeds/manual.json"),
    join(here, "../../../packages/ingest/seeds/manual.json")
  ].filter((path): path is string => Boolean(path));

  for (const candidate of candidates) {
    try {
      return await readFile(candidate, "utf8");
    } catch {
      continue;
    }
  }

  throw new Error("manual seed file not found; set WAT_SEED_PATH");
}

async function publicEntries(): Promise<WatEntry[]> {
  const parsed = JSON.parse(await readSeedJson()) as { entries: WatEntry[] };
  return parsed.entries.filter((entry) => entry.layer === "public");
}

function toResult(entry: WatEntry, score: number): WatResult {
  return {
    citations: entry.sources,
    confidence_tier: entry.confidence_tier,
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
  const domain = entry.domains.some((value) => value.toLowerCase().includes(normalized)) ? 0.4 : 0;
  const body = entry.meaning_short.toLowerCase().includes(normalized) ? 0.25 : 0;
  const contextBoost = entry.domains.some((value) => contextText.includes(value.toLowerCase()))
    ? 0.3
    : 0;

  return toResult(entry, exact + expansion + domain + body + contextBoost);
}

export async function lookupEntries(input: {
  auth: AuthContext;
  context?: string;
  limit?: number;
  min_confidence?: ConfidenceTier;
  term: string;
}): Promise<WatResult[]> {
  const minConfidence = input.min_confidence ?? "T4";
  const entries = [...devTeamEntries, ...(await publicEntries())].filter((entry) => {
    if (confidenceRank[entry.confidence_tier] > confidenceRank[minConfidence]) {
      return false;
    }
    if (entry.layer === "team") {
      return entry.team_id === input.auth.team_id;
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
      return `${result.term}: ${result.expansion} (${result.confidence_tier}, ${result.layer})\n${result.meaning}\nSources: ${citations}`;
    })
    .join("\n\n");
}
