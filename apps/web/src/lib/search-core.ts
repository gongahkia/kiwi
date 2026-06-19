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
  const layer = entry.layer === "personal" ? 0.75 : entry.layer === "team" ? 0.5 : 0;
  const score = exact + expansion + domain + body + layer;

  return {
    entry,
    score,
    score_breakdown: {
      bm25: exact + expansion + body,
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
