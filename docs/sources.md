# Sources

Source registry for implemented scrapers and committed seed data.

## Implemented Scrapers

| Scraper | Publisher | License | Refresh | Notes |
| --- | --- | --- | --- | --- |
| `example` | wat fixture | MIT | manual | Local ingestion CLI fixture in `packages/ingest/src/scrapers/example.ts`. |

## Manual Seed Sources

| Publisher | License | Source URL | Notes |
| --- | --- | --- | --- |
| MDN Web Docs | CC-BY-SA-2.5 | https://developer.mozilla.org/ | Seeded web platform terms. |
| Wikipedia | CC-BY-SA-4.0 | https://en.wikipedia.org/ | Seeded acronym and disambiguation entries. |
| Kubernetes | CC-BY-4.0 | https://kubernetes.io/docs/reference/glossary/ | Seeded Kubernetes glossary terms. |

## Review Rules

- Every public entry needs at least one source URL and license.
- Scraper output must preserve publisher, title, retrieved timestamp, snippet, source quality, and license.
- License changes must be reviewed before a corpus delta is merged.
- Sources with non-commercial, no-derivatives, unclear, or conflicting terms require explicit review before import.
