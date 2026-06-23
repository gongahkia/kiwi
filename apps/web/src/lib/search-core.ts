import type { SearchEntry, SearchResult } from "@wat/search";

export const confidenceRank = {
  T1: 1,
  T2: 2,
  T3: 3,
  T4: 4
} as const;

const layerRank = {
  personal: 3,
  public: 1,
  team: 2
} as const;

export interface SearchEntriesInput {
  entries: SearchEntry[];
  limit?: number;
  minConfidence?: keyof typeof confidenceRank | null;
  query: string;
}

export function searchEntries({
  entries,
  limit = 10,
  minConfidence,
  query
}: SearchEntriesInput): SearchResult[] {
  if (!query.trim()) return [];

  const rankedMatches = sortMatches(
    entries
      .filter(
        (entry) =>
          !minConfidence || confidenceRank[entry.confidence_tier] <= confidenceRank[minConfidence]
      )
      .map((entry) => scoreEntry(query, entry))
      .filter((result): result is SearchResult => result != null)
  );

  return rankedMatches.slice(0, Number.isFinite(limit) && limit > 0 ? limit : 10);
}

export function scoreEntry(query: string, entry: SearchEntry): SearchResult | null {
  const normalized = query.toLowerCase().trim();
  const queryTokens = normalized.split(/\s+/).filter(Boolean);

  function includesQuery(value: string): boolean {
    const lower = value.toLowerCase();
    return lower.includes(normalized) || queryTokens.some((token) => lower.includes(token));
  }

  const exact =
    entry.term_normalized === normalized || queryTokens.includes(entry.term_normalized) ? 1 : 0;
  const expansion = entry.expansions.some(includesQuery) ? 0.8 : 0;
  const contemporary = entry.contemporaries.some(includesQuery) ? 0.35 : 0;
  const domain = entry.domains.some(includesQuery) ? 0.4 : 0;
  const body = includesQuery(entry.meaning_short) ? 0.25 : 0;
  const layer = entry.layer === "personal" ? 0.75 : entry.layer === "team" ? 0.5 : 0;
  const score = exact + expansion + contemporary + domain + body + layer;

  if (exact + expansion + contemporary + domain + body === 0) {
    return null;
  }

  return {
    entry,
    score,
    score_breakdown: {
      bm25: exact + expansion + body,
      contemporary,
      domain,
      layer
    }
  };
}

export function sortMatches(results: SearchResult[]): SearchResult[] {
  return [...results].sort(
    (left, right) =>
      right.score - left.score ||
      layerRank[right.entry.layer] - layerRank[left.entry.layer] ||
      left.entry.id.localeCompare(right.entry.id)
  );
}
