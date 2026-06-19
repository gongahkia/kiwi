# wat

## One-liner
Multi-surface OSS glossary for tech + team-specific acronyms and jargon. Web app, browser ext, Slack app, MCP server. Decode onboarding, meetings, and unfamiliar codebases without LLM hallucination.

## Problem
- New hires drown in team-local acronyms (internal product codes, vendor names, ops shorthand).
- Public tech jargon is scattered: Wikipedia, RFCs, Jargon File, MDN, IEEE, vendor docs.
- Existing tools are either heavy SaaS (Glean, Slab, Tettra) or toy CLIs (`wtf-cli`, `abbr-cli`) w/ <1K entries and no team layer.
- LLMs hallucinate definitions, can't see team-private terms, and aren't authoritative.

## Solution
Three-layer glossary, four surfaces, hybrid search, zero unsourced claims.
- Layers: public corpus → team overlay → personal overlay. Merged w/ source attribution.
- Surfaces: web, browser ext (Chrome/Firefox), Slack app, MCP server.
- Search: Postgres FTS + pgvector cosine + trigram fuzzy → Reciprocal Rank Fusion. Domain/context-aware disambiguation.

## Non-goals
- No AI-only unsourced definitions. Every entry cites or is marked unsourced.
- No general English dictionary. Acronyms, initialisms, jargon, overloaded terms only.
- No required external API for lookup. Self-host == fully functional.
- No CLI surface (MCP covers coding-agent use). No corporate-shaming/satire tone.
- No Raspberry Pi constraint.

## Stack
- Web: Next.js (App Router) + TypeScript.
- DB: Postgres 16 + pgvector + pg_trgm.
- ORM: Drizzle.
- Search: Postgres FTS (`tsvector`) + pgvector cosine + trigram fuzzy, fused via RRF.
- Embeddings: `bge-small-en-v1.5` via Transformers.js (self-host-friendly). Optional Voyage/OpenAI providers.
- Auth: NextAuth — email magic-link, Slack OAuth, Google OAuth. Email-domain auto-team.
- Browser ext: WXT framework (MV3, Chrome + Firefox).
- Slack app: Bolt for TypeScript.
- MCP server: `@modelcontextprotocol/sdk` (TS), read-only.
- Hosting: docker compose for self-host; Vercel/Railway/Fly for hosted.
- Ingestion: scheduled GitHub Actions → JSON deltas → PR review → merge.

## Public corpus seeds (v0.1)
Wikipedia acronym disambiguation, IETF RFC index, Jargon File / New Hacker's Dictionary, `d-edge/foss-acronyms`, MDN glossary, W3C terminology, Cloud Native Glossary (CNCF), Google SRE book glossary, AWS/GCP/Azure service-name expansions, NIST CSRC glossary (public-domain). Target 5K–20K entries at launch.

## Confidence tiering
- T1 high: multi-source agreement + canonical citation (RFC, ISO, IEEE, vendor docs).
- T2 medium: one canonical source.
- T3 low: scraped only, no canonical citation.
- T4 user-contributed: requires moderation.
Default UI hides T3/T4 unless toggled.

## Disambiguation
Same acronym, multiple expansions across domains (eg. CAP = Consistency-Availability-Partition vs Common Agricultural Policy). Ranking inputs: user/team domain tags, surrounding context string (MCP/ext sidebar), per-entry source weight, click-through priors.

## Team layer
Tenancy = email domain at signup. Team admin can add/edit/override/delete team entries, tag domains, manage members. Members can read all and suggest edits (queued for admin review). Future: Slack-workspace tenancy as alternative.

## Surfaces
- Web: search, entry pages w/ citations & history, suggest-edit, team admin, install hubs for ext/Slack/MCP.
- Browser ext: hover-explain, sidebar, context-menu lookup, opt-in auto-highlight of unknown acronyms in page.
- Slack: `/wat <term>` slash command, message shortcut "Explain acronyms here", @mention bot.
- MCP: `lookup(term, context?)`, `list_team_acronyms(domain?)`. Read-only.

## Acceptance criteria
- Search p95 < 150ms hosted; < 300ms self-host on a 2-core box.
- ≥ 90% hit rate on a benchmark of 500 curated dev-tooling acronyms.
- Zero fabricated results — unknown returns `no-match` with suggest CTA.
- Every public entry has source URL + license tag.
- `docker compose up` boots full stack on a clean machine in < 5 min.
- Public corpus refresh job runs weekly, produces a diff PR.

## Virality plan
- v0.1 launch: Show HN lead w/ browser-ext demo GIF + MCP integration GIF.
- Cross-post r/programming, r/devops, r/slackapps, Lobsters.
- Submit to Slack App Directory, Chrome Web Store, Firefox add-ons.
- Submit MCP to Cursor + Claude Desktop catalogs.
- Pitch story: "the OSS glossary that ships everywhere you already work."

## Root files
Keep `idea.md` and `todo.md` at project root regardless of folder rename.
