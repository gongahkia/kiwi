# Scraper Authoring

Scrapers implement `ScraperPlugin` from `packages/ingest/src/scraper.ts`.

```ts
export interface ScraperPlugin {
  name: string;
  license: string;
  refresh_interval: string;
  fetch(): AsyncIterable<RawEntry>;
}
```

## Working Example

```ts
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
```

Register a scraper in `packages/ingest/src/scrapers/index.ts`, then run:

```sh
pnpm ingest run example
```

The CLI writes a JSON delta to `data/deltas/<date>/<source>.json`.

If a merged delta is bad, restore it from a known-good git ref with the [corpus delta rollback runbook](corpus-rollback.md).

## Rules

- `name` must match the CLI source name.
- `license` must describe the scraper output license policy.
- Every raw entry must include at least one source unless it is intentionally user-contributed later in the pipeline.
- Every source license must be a known compatible SPDX ID; unknown or incompatible IDs fail ingestion.
- `retrieved_at` must be an ISO timestamp captured when the source was fetched.
- `source_quality` should be `canonical`, `secondary`, or `community`; omitted values default to `secondary`.
