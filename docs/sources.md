# Sources

Source registry for implemented scrapers and committed seed data.

## Implemented Scrapers

| Scraper | Publisher | License | Refresh | Notes |
| --- | --- | --- | --- | --- |
| `aws-services` | AWS SDK for JavaScript | Apache-2.0 | weekly | AWS service identifiers and expansions from SDK package metadata. |
| `azure-services` | Azure REST API Specs | MIT | weekly | Azure service names from public REST API specification paths. |
| `cloud-service-comparison` | Google Cloud Documentation | CC-BY-4.0 | weekly | Cross-cloud AWS/Azure/GCP service comparison rows. |
| `cncf-glossary` | CNCF Cloud Native Glossary | CC-BY-4.0 | weekly | Cloud-native glossary terms with published CNCF URLs. |
| `cncf-landscape` | CNCF Landscape | Apache-2.0 | weekly | CNCF project/product names grouped by landscape category. |
| `d-edge-foss-acronyms` | d-edge/foss-acronyms | CC0-1.0 | weekly | Community FOSS acronym expansions. |
| `example` | wat fixture | MIT | manual | Local ingestion CLI fixture in `packages/ingest/src/scrapers/example.ts`. |
| `gcp-services` | Google API Node.js Client | Apache-2.0 | weekly | Google Cloud service identifiers and package metadata. |
| `github-glossary` | GitHub glossary source | configurable | manual | Raw repo or wiki `GLOSSARY.md` tables/headings via `GITHUB_GLOSSARY_*`. |
| `ietf-rfc-index` | IETF RFC Index | LicenseRef-IETF-TLP-5.0 | weekly | RFC titles and identifiers from the public RFC index. |
| `jargon-file` | Jargon File | LicenseRef-Public-Domain | manual | Historical computing jargon entries from the Jargon File. |
| `kubernetes-glossary` | Kubernetes Documentation | CC-BY-4.0 | weekly | Kubernetes glossary entries with docs anchors. |
| `linux-foundation-glossary` | LF Edge Open Glossary of Edge Computing | CC-BY-SA-4.0 | weekly | Edge-computing glossary terms from LF Edge. |
| `mdn-glossary` | Mozilla Contributors | CC-BY-SA-2.5 | weekly | MDN glossary terms. |
| `mdn-web-technology` | Mozilla Contributors | CC-BY-SA-2.5 | weekly | MDN Web technology pages and APIs. |
| `nist-csrc-glossary` | NIST CSRC Glossary | NIST-PD | daily | NIST cybersecurity glossary terms. |
| `postgresql-extensions` | PostgreSQL and extension projects | mixed | weekly | PostgreSQL extension/product entries with per-source license metadata. |
| `postgresql-glossary` | PostgreSQL Documentation | PostgreSQL | weekly | PostgreSQL glossary terms. |
| `w3c-glossary` | W3C Glossary and Dictionary | W3C | weekly | W3C glossary keyword definitions. |
| `wikipedia-acronyms` | Wikipedia contributors | CC-BY-SA-4.0 | weekly | Curated acronym/disambiguation pages. |
| `wikipedia-outline` | Wikipedia contributors | CC-BY-SA-4.0 | weekly | Curated systems/products/concepts from Wikipedia outlines/templates. |

## Manual Seed Sources

| Publisher | License | Source URL | Notes |
| --- | --- | --- | --- |
| MDN Web Docs | CC-BY-SA-2.5 | https://developer.mozilla.org/ | Seeded web platform terms. |
| Wikipedia | CC-BY-SA-4.0 | https://en.wikipedia.org/ | Seeded acronym and disambiguation entries. |
| Kubernetes | CC-BY-4.0 | https://kubernetes.io/docs/reference/glossary/ | Seeded Kubernetes glossary terms. |
| wat fixture | MIT | https://example.com/wat/community/ | Low-confidence UI verification fixtures. |

## Review Rules

- Every public entry needs at least one source URL and license.
- Scraper output must preserve publisher, title, retrieved timestamp, snippet, source quality, and license.
- License changes must be reviewed before a corpus delta is merged.
- Sources with non-commercial, no-derivatives, unclear, or conflicting terms require explicit review before import.
