import type { SearchResult, SearchScoreBreakdown } from "./api.js";

export interface DisambiguationResult {
  domains: string[];
  entry_id: string;
  expansion: string;
  score: number;
  score_breakdown: SearchScoreBreakdown;
  term: string;
}

export function groupDisambiguations(results: SearchResult[]): DisambiguationResult[] {
  return results
    .map((result) => ({
      domains: result.entry.domains,
      entry_id: result.entry.id,
      expansion: result.entry.expansions[0] ?? result.entry.term,
      score: result.score,
      score_breakdown: result.score_breakdown,
      term: result.entry.term
    }))
    .sort((left, right) => right.score - left.score || left.entry_id.localeCompare(right.entry_id));
}
