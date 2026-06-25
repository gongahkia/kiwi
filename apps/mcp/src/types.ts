export type ConfidenceTier = "T1" | "T2" | "T3" | "T4";
export type EntryLayer = "public" | "team" | "personal";
export type SourceQuality = "canonical" | "secondary" | "community";

export interface WatSource {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  source_quality: SourceQuality;
  title: string;
  url: string;
}

export interface WatEntry {
  aliases: string[];
  confidence_tier: ConfidenceTier;
  contemporaries: string[];
  domains: string[];
  expansions: string[];
  id: string;
  layer: EntryLayer;
  meaning_short: string;
  sources: WatSource[];
  term: string;
  term_normalized: string;
  team_id?: string | null;
}

export interface WatResult {
  citations: WatSource[];
  confidence_tier: ConfidenceTier;
  contemporaries: string[];
  domains: string[];
  entry_id: string;
  expansion: string;
  layer: EntryLayer;
  meaning: string;
  score: number;
  term: string;
}

export interface WatAlternativesResult {
  alternatives: WatResult[];
  entry: WatResult | null;
  unresolved_terms: string[];
}
