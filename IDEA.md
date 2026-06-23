# wat

## One-liner
Multi-surface OSS decoder for tech terms (acronyms, concepts, systems) and team-specific jargon. Web app, browser ext, Slack app, MCP server. Decode onboarding, meetings, and unfamiliar codebases without LLM hallucination. Every entry cites sources and lists peer alternatives ("contemporaries") so users build mental models, not just lookups.

## Problem
- New hires drown in team-local acronyms AND broader unfamiliar tech concepts/systems (Azure, Kubernetes, "hosting", service mesh, RBAC, OIDC) thrown around by senior devs.
- Public tech jargon is scattered: Wikipedia, RFCs, Jargon File, MDN, IEEE, CNCF, vendor docs. No single source gives a definition + cite + "things this is like" in one place.
- Closest existing tool: GlossaryTech (Chrome ext, recruiter-focused, closed-source) covers definitions but has no team layer, no Slack/MCP, no contemporaries. Heavy SaaS (Glean, Slab, Tettra) is too enterprise. Toy CLIs (`wtf-cli`, `abbr-cli`) have <1K entries.
- LLMs hallucinate definitions, can't see team-private terms, and aren't authoritative.
- Even when you find a definition, you often need to know "what's the AWS equivalent of Azure Functions" or "what else competes w/ Kafka" — no glossary systematizes that.

## Solution
Three-layer glossary, four surfaces, hybrid search, zero unsourced claims, peer alternatives on every entry.
- Layers: public corpus → team overlay → personal overlay. Merged w/ source attribution.
- Surfaces: web, browser ext (Chrome/Firefox), Slack app, MCP server.
- Search: Postgres FTS + pgvector cosine + trigram fuzzy → Reciprocal Rank Fusion. Domain/context-aware disambiguation.
- Scope: tech terms = acronyms (RBAC, OIDC) + concepts (hosting, idempotency, eventual consistency) + systems/products (Azure, Kubernetes, Kafka). Not general English. Not team-local code identifiers unless explicitly added to a team overlay.
- Contemporaries: each entry has a `contemporaries` field listing peer alternatives (Kafka → RabbitMQ, NATS, Redpanda; Azure → AWS, GCP, OCI). Rendered as a one-line "Alternatives" block on entry pages. Crosslinks when present in corpus.

## Non-goals
- No AI-only unsourced definitions. Every entry cites or is marked unsourced.
- No general English dictionary. Tech terms (acronyms, concepts, systems) only — not words like "schedule" or "approval".
- No required external API for lookup. Self-host == fully functional.
- No CLI surface (MCP covers coding-agent use). No corporate-shaming/satire tone. No brainrot/Gen-Z slang mode (kills rigor positioning).
- No meeting-mic capture, real-time STT, or "panic button" surface. Same lookup moment is covered by the browser ext sidebar + Slack message-shortcut without privacy/STT complexity.
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
Acronym/jargon sources: Wikipedia acronym disambiguation, IETF RFC index, Jargon File / New Hacker's Dictionary, `d-edge/foss-acronyms`, MDN glossary, W3C terminology, Cloud Native Glossary (CNCF), Google SRE book glossary, AWS/GCP/Azure service-name expansions, NIST CSRC glossary (public-domain).
Concept/system sources (added 2026-06-23 w/ scope expansion): Wikipedia "Outline of computer science" + "Glossary of computer science" + "Outline of computing" (CC-BY-SA), MDN "Web technology for developers" concept index (CC-BY-SA-2.5), CNCF Landscape (cncf/landscape, Apache-2.0), Kubernetes glossary, Postgres extensions registry.
Cross-cloud contemporaries source of truth: GCP's published AWS/Azure/GCP service comparison doc — used to seed `contemporaries` on cloud service entries.
Target 5K–20K entries at launch.

## Contemporaries
Peer-alternatives field on every entry. Distinct from `related_terms` (adjacent: Kubernetes→pods, kubelet) — contemporaries are competitors/substitutes (Kubernetes→Docker Swarm, Nomad, ECS).
- Stored as `text[]` on `entries`, `team_entries`, `personal_entries`. Indexed in tsvector at weight `D` so contemporaries match in full-text search.
- Symmetric: if A lists B, B should list A. CI lint enforces symmetry + flags unresolved names.
- Coverage gate: ≥60% of public entries in cloud/devops/observability/storage domains have ≥1 contemporary at launch.
- Surfaces render as a one-line "Alternatives" block (web entry page, ext sidebar, Slack ephemeral response, MCP lookup response).
- Seed strategy: scrape what's automatable (GCP service comparison, CNCF Landscape categories), then a manual curation pass on top-200 most-likely-searched concepts/systems committed as a delta JSON.

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
- Web: search, entry pages w/ citations & history + "Alternatives" block, suggest-edit, team admin, install hubs for ext/Slack/MCP.
- Browser ext: hover-explain w/ inline "Alt: X, Y, Z" line, sidebar w/ Alternatives section, context-menu lookup, opt-in auto-highlight of unknown terms in page.
- Slack: `/wat <term>` slash command (appends "Alternatives:" line when populated), message shortcut "Explain acronyms here", @mention bot, `/wat-alt <term>` lists peer alternatives only.
- MCP: `lookup(term, context?)` (returns `contemporaries: string[]`), `list_alternatives(term)`, `list_team_acronyms(domain?)`. Read-only.

## Acceptance criteria
- Search p95 < 150ms hosted; < 300ms self-host on a 2-core box.
- ≥ 90% top-1 / ≥ 98% top-5 hit rate on an expanded benchmark of 1000 mixed entries (500 acronyms + 300 concepts + 200 systems).
- Zero fabricated results — unknown returns `no-match` w/ suggest CTA.
- Every public entry has source URL + license tag.
- ≥ 60% of public entries in cloud/devops/observability/storage domains have ≥ 1 contemporary populated at launch.
- Alternatives block renders correctly across web, ext, Slack, MCP for ≥ 5 reference entries (Kubernetes, Kafka, Postgres, Terraform, Datadog) — verified by E2E.
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
