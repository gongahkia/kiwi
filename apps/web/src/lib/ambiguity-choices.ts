import type { ConfidenceTier, EntryLayer, SearchResult } from "@wat/search";

export interface AmbiguityChoice {
  confidence_tier: ConfidenceTier;
  domains: string[];
  entry_id: string;
  expansion: string;
  layer: EntryLayer;
  score: number;
  term: string;
}

export function ambiguityChoices(query: string, results: SearchResult[]): AmbiguityChoice[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return [];

  const exactMatches = results.filter((result) => result.entry.term_normalized === normalized);
  const expansionCount = new Set(
    exactMatches.map((result) => result.entry.expansions[0] ?? result.entry.term)
  ).size;
  if (expansionCount < 2) return [];

  return [...exactMatches]
    .sort((left, right) => right.score - left.score || left.entry.id.localeCompare(right.entry.id))
    .map((result) => ({
      confidence_tier: result.entry.confidence_tier,
      domains: result.entry.domains,
      entry_id: result.entry.id,
      expansion: result.entry.expansions[0] ?? result.entry.term,
      layer: result.entry.layer,
      score: result.score,
      term: result.entry.term
    }));
}
