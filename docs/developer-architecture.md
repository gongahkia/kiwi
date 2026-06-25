# Developer Architecture Guide

This guide is for contributors working on DB-backed public, team, and personal layers.

## Layer Ownership

| Layer | Target table | Owner | Visibility |
| --- | --- | --- | --- |
| Public | `entries` plus `sources` and `examples` | reviewed corpus imports | anonymous and authenticated users |
| Team | `team_entries` plus normalized team sources | wat team admins/integrations | users or keys scoped to the team |
| Personal | `personal_entries` plus normalized personal sources | one user | that user only |

Layer priority is `personal > team > public`. If the same term appears in multiple visible layers, the more specific layer should rank first and the UI should preserve provenance.

## Target DB-Backed Flow

```mermaid
flowchart TD
  public_import[reviewed corpus import] --> entries[(entries)]
  team_write[team admin/API/Slack/Discord import] --> team_entries[(team_entries)]
  personal_write[web/extension personal save] --> personal_entries[(personal_entries)]
  entries --> repo[entry repositories]
  team_entries --> repo
  personal_entries --> repo
  repo --> search_api[/api/v1/search]
  search_api --> rank[@wat/search ranking]
  rank --> surfaces[web, extension, Slack, Discord, MCP, LSP]
  team_write --> audit[(audit_log)]
  personal_write --> audit
```

Repository interfaces should hide storage details from route handlers. The search route should ask repositories for entries visible to the resolved identity, then pass a merged list to the ranking layer.

## Request Identity

Search and write paths resolve identity before touching private data.

- Anonymous identity can read only public entries.
- API identity may include API key, user ID, and team ID headers.
- Session identity should come from NextAuth for web routes.
- Slack, Discord, and extension requests should map to the same team/user model before reading private layers.
- MCP currently accepts `api_key` tool input, but hosted mode should resolve DB-backed per-team keys.

## Search Route Shape

Target `/api/v1/search` sequence:

1. Resolve identity.
2. Apply rate limits by IP, user, team, or key.
3. Load public entries.
4. Load team entries when identity has team scope.
5. Load personal entries when identity has user scope.
6. Rank visible entries with `@wat/search`.
7. Log privacy-safe query hash, layer hits, confidence distribution, and latency.
8. Return cited results with layer and confidence labels.

Current dev route still reads public seed JSON and in-memory team/personal stores through `apps/web/src/lib/search-data.ts`; the TODO backlog tracks replacing those stores with DB repositories.

## Writes And Audit

Mutations should write the target row and audit row together.

- Team CRUD/import writes `team_entries` and `audit_log`.
- Personal saves write `personal_entries` and user-scoped audit where applicable.
- Suggestions write `suggested_edits`; approval writes the target entry plus audit.
- API key changes, member changes, settings changes, and integration installs should also audit.

Audit summaries must not store raw API keys, OAuth tokens, magic links, session cookies, or unnecessary private definition bodies.

## Surface Expectations

- Web uses session auth for interactive admin, personal, suggestion, and search flows.
- Browser extension sends term/context and auth headers to web API; it should not bypass route checks.
- Slack handlers call the same hosted API and include scoped wat auth headers.
- Discord handlers call the same hosted API, include scoped wat auth headers, and verify Discord signatures before parsing interactions.
- MCP tools should use the same API or repository layer as web once hosted/DB-backed support lands.
- LSP/editor surfaces should remain read-only unless a write flow gets explicit auth and audit coverage.

## Files To Read First

- `packages/db/src/schema.ts`: Drizzle tables and indexes.
- `docs/db-schema.md`: schema diagram and generated/indexed columns.
- `apps/web/src/app/api/v1/search/route.ts`: current search API path.
- `apps/web/src/lib/search-data.ts`: current bridge from seed/in-memory stores to search entries.
- `apps/web/src/lib/team-entries.ts`, `personal-entries.ts`, `suggestions.ts`, `audit-log.ts`: current stores to replace with repositories.
- `packages/search/src/api.ts`: shared search entry/result types.
