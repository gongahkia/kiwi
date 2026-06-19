export interface RawSourceCitation {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet?: string;
  title?: string;
  url: string;
}

export interface RawEntry {
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
