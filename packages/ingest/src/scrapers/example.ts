import type { ScraperPlugin } from "../scraper.js";

export const exampleScraper: ScraperPlugin = {
  name: "example",
  license: "MIT",
  refresh_interval: "manual",
  async *fetch() {
    yield {
      domains: ["distributed systems"],
      expansion: "Consistency Availability Partition tolerance",
      meaning:
        "A distributed-systems tradeoff among consistency, availability, and partition tolerance.",
      sources: [
        {
          license: "MIT",
          publisher: "wat fixture",
          retrieved_at: "2026-01-01T00:00:00.000Z",
          snippet: "Fixture entry for local ingestion CLI verification.",
          source_quality: "secondary",
          title: "Example CAP entry",
          url: "https://example.com/wat/cap"
        }
      ],
      term: "CAP"
    };
  }
};
