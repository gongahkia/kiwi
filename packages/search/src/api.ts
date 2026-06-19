export type ConfidenceTier = "T1" | "T2" | "T3" | "T4";
export type EntryLayer = "public" | "team" | "personal";
export type SourceQuality = "canonical" | "secondary" | "community";

export interface SearchSource {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  source_quality: SourceQuality;
  title: string;
  url: string;
}

export interface SearchEntry {
  aliases: string[];
  confidence_tier: ConfidenceTier;
  domains: string[];
  expansions: string[];
  id: string;
  layer: EntryLayer;
  meaning_short: string;
  sources: SearchSource[];
  term: string;
  term_normalized: string;
}

export interface SearchRequest {
  query: string;
  context?: string;
  team_id?: string;
  layers?: EntryLayer[];
  min_confidence?: ConfidenceTier;
  limit?: number;
}

export interface SearchScoreBreakdown {
  bm25?: number;
  context?: number;
  domain?: number;
  rrf?: number;
  trigram?: number;
  vector?: number;
}

export interface SearchResult {
  entry: SearchEntry;
  score: number;
  score_breakdown: SearchScoreBreakdown;
}

export interface SearchResponse {
  matches: SearchResult[];
  suggest_url?: string;
}

export type SearchApi = (request: SearchRequest) => Promise<SearchResponse>;
