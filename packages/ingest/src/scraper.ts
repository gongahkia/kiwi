export interface RawSourceCitation {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet?: string;
  source_quality?: "canonical" | "secondary" | "community";
  title?: string;
  url: string;
}

export interface RawEntry {
  aliases?: string[];
  contemporaries?: string[];
  domains?: string[];
  examples?: string[];
  expansion?: string;
  meaning?: string;
  sources: RawSourceCitation[];
  term: string;
}

export interface ScraperPlugin {
  name: string;
  license: string;
  refresh_interval: string;
  fetch(): AsyncIterable<RawEntry>;
}
