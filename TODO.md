# wat — Todo

Format: `- [ ] task — done when <condition>`. Phases run roughly in order; tasks within a phase can parallelize unless noted.

## Non-goals reminder
- No AI-only unsourced definitions. Every result cites or is marked unsourced.
- No general English dictionary. Acronyms/initialisms/jargon/overloaded terms only.
- No required external API for lookup. Self-host == fully usable.
- No CLI surface, no satire/shame tone, no Pi constraint.

## P0 — Repo & schema foundation
- [ ] Reserve npm scope `@wat` — done when `npm view @wat/core` returns 404 → publish placeholder.
- [ ] Reserve domain candidates — done when at least two of `wat.dev`, `getwat.dev`, `wat.tools` are availability-checked and one secured.
- [ ] Reserve GitHub org `wat` or fallback — done when org exists and repo `wat/wat` is created.
- [ ] Set up GitHub Actions CI matrix (lint, typecheck, test, build) — done when CI green on `main` w/ all jobs.
- [ ] Hand-curate 50 high-quality seed entries in `packages/ingest/seeds/manual.json` — done when JSON validates against schema and includes ≥3 disambiguation cases (eg. CAP, SLA, REST).

## P0 — Database & migrations
- [ ] Create `sources` table FK to entries — done when migration applies and FK enforces cascade.
- [ ] Create `examples` table FK to entries — done when migration applies.
- [ ] Add GIN index on `entries.tsvector` — done when `\d entries` shows index of type gin.
- [ ] Add ivfflat or HNSW index on `entries.embedding` — done when index exists and EXPLAIN uses it on cosine query.
- [ ] Add trigram index on `entries.term_normalized` — done when GIN trgm index exists.
- [ ] Add unique partial index `(term_normalized, layer, team_id)` — done when duplicate insert across same layer is rejected.
- [ ] Seed migration script for dev DB — done when `pnpm db:seed:dev` populates 50 manual entries.
- [ ] Write DB integration tests for CRUD + tsvector regeneration — done when `pnpm test --filter @wat/db` passes ≥10 cases.

## P0 — Core package
- [ ] Implement entry validator (Zod + business rules) — done when all 50 seed entries validate.

## P1 — Search engine
- [ ] Implement BM25-ish query via Postgres `ts_rank_cd` — done when query returns ranked entries for 20 fixture queries.
- [ ] Set up embedding pipeline using `bge-small-en-v1.5` via Transformers.js — done when `embed("CAP theorem")` returns a 384-dim float32 vector in <100ms warm.
- [ ] Backfill embeddings for all entries on insert/update — done when DB trigger or app-level enqueue ensures coverage; spot-check 100 entries.
- [ ] Implement vector similarity query w/ cosine distance — done when query returns ranked entries by cosine for 20 fixtures.
- [ ] Implement trigram fuzzy fallback for typos — done when "kuberntes" → "Kubernetes" ranks top-3.
- [ ] Implement Reciprocal Rank Fusion combiner — done when weighted combo of BM25 + vector + trigram outperforms any single signal on benchmark.
- [ ] Implement domain/context boost — done when passing `context: "distributed systems"` raises CAP-theorem above CAP-agricultural-policy.
- [ ] Implement disambiguation grouping (1 query → N expansions w/ scores) — done when API returns array sorted by score w/ score breakdown.
- [ ] Build benchmark corpus of 500 dev-tooling acronyms — done when JSON file committed w/ query + expected answer.
- [ ] Run benchmark on hybrid search — done when hit-rate ≥90% on top-1 and ≥98% on top-5.
- [ ] Measure search latency on hosted (Vercel + Neon) — done when p95 < 150ms for 1k-warmup queries.
- [ ] Measure search latency on self-host (single docker compose, 2-core) — done when p95 < 300ms.
- [ ] Add search analytics events (no PII) — done when each search logs query_hash, latency, layer_hit, confidence_distribution.

## P1 — Public corpus ingestion framework
- [ ] Build delta-to-PR workflow via GitHub Actions — done when scheduled run opens a PR titled `corpus: refresh <source> <date>` with the JSON delta diff.
- [ ] Implement reviewer-friendly PR summary (counts added/changed/removed, sample diffs) — done when PR body shows summary table.
- [ ] Set up weekly cron (Sun 03:00 UTC) — done when `.github/workflows/corpus-refresh.yml` runs on schedule.

## P1 — Public corpus scrapers (one task per source)
- [ ] Wikipedia acronym/disambiguation scraper — done when ≥3K entries imported w/ Wikipedia citations, license CC-BY-SA tagged.
- [ ] IETF RFC index scraper (RFCs that define acronyms) — done when ≥500 RFC-anchored acronyms imported (eg. TCP, BGP, SMTP) w/ RFC number + section.
- [ ] Jargon File / New Hacker's Dictionary parser (public domain) — done when full file ingested, ≥2K entries.
- [ ] `d-edge/foss-acronyms` ingester (JSON pull) — done when upstream JSON merged w/ provenance.
- [ ] MDN glossary scraper (CC-BY-SA 2.5) — done when ≥600 web-platform terms ingested.
- [ ] W3C glossary scraper — done when standards terms ingested w/ W3C URLs.
- [ ] CNCF Cloud Native Glossary scraper (CC-BY 4.0) — done when ≥120 cloud-native terms ingested.
- [ ] Google SRE book glossary scraper (CC-BY-NC-ND check) — done when terms ingested only if license permits; else excluded w/ note.
- [ ] AWS service-name expansion scraper (EC2 → Elastic Compute Cloud) — done when ≥200 AWS services covered.
- [ ] GCP service-name expansion scraper — done when ≥150 GCP services covered.
- [ ] Azure service-name expansion scraper — done when ≥150 Azure services covered.
- [ ] NIST CSRC glossary scraper (public domain) — done when ≥1K security terms ingested.
- [ ] Linux Foundation glossary scraper — done when LF-published terms ingested where licensed.
- [ ] PostgreSQL glossary scraper — done when Postgres-doc terms ingested.
- [ ] Kubernetes glossary scraper — done when k8s-doc terms ingested w/ CC-BY 4.0.
- [ ] Document each source's license in `docs/sources.md` — done when each scraper has matching entry.

## P1 — Corpus quality controls
- [ ] Build sanity-check linter: every public entry has ≥1 source, every T1 has canonical-flagged source — done when `pnpm ingest lint` passes.
- [ ] Build benchmark gate: corpus refresh PR is blocked if hit-rate drops >1pp — done when PR check fails in test scenario.
- [ ] Build corpus stats dashboard page in web app — done when `/stats` shows entry counts by source, tier, domain.

## P2 — Web app foundation
- [ ] Scaffold Next.js 15 App Router project in `apps/web` — done when `pnpm dev --filter @wat/web` serves at :3000.
- [ ] Configure Tailwind + shadcn/ui — done when a sample button page renders.
- [ ] Configure dark mode via `next-themes` — done when toggle works persistently.
- [ ] Configure middleware for auth-protected routes — done when `/team/admin` redirects to login when unauth.
- [ ] Set up NextAuth w/ email magic-link provider — done when end-to-end magic-link login works locally w/ Mailpit.
- [ ] Add Google OAuth provider — done when Google login produces a session.
- [ ] Add Slack OAuth provider — done when Slack login produces a session.
- [ ] Implement email-domain → auto-team join on signup — done when two users w/ same domain land in same team automatically.
- [ ] Implement team creation on first signup of a new domain — done when team row created and user is admin.
- [ ] Implement role guards (admin / member) — done when non-admin gets 403 on admin endpoints.
- [ ] Add Sentry or self-host error tracking — done when a thrown error in prod surfaces in dashboard.
- [ ] Add structured logging (pino) — done when each request emits a JSON log w/ request_id.

## P2 — Web app: search UX
- [ ] Build landing page w/ search box as hero — done when search box autofocuses, debounces, and renders results.
- [ ] Build search API route `/api/v1/search` — done when GET returns merged-layer typed JSON.
- [ ] Implement instant-search w/ React Server Components + Suspense — done when typing shows results in <200ms perceived.
- [ ] Implement result card component — done when card shows acronym, top expansion, domain, confidence chip, source count.
- [ ] Implement disambiguation expansion (multiple expansions) UI — done when CAP shows 2+ cards w/ domain labels.
- [ ] Implement confidence-tier toggle — done when T3/T4 entries hidden by default, revealed by toggle.
- [ ] Implement domain filter dropdown — done when filter narrows results live.
- [ ] Implement keyboard nav (arrows + enter) — done when nav works without mouse.
- [ ] Implement entry detail page `/term/[id]` — done when page renders meaning, examples, sources w/ links, history.
- [ ] Implement copy-citation button — done when click copies Markdown citation to clipboard.
- [ ] Implement permalink + share-link UI — done when share URL resolves back to entry.
- [ ] Implement Open Graph image generation per entry — done when entry page meta has og:image w/ acronym + expansion.
- [ ] Add sitemap.xml generator — done when `/sitemap.xml` lists all public entries.
- [ ] Add robots.txt — done when file allows public pages, disallows admin/api.
- [ ] Add 404 page w/ search suggestion — done when unknown term routes here.

## P2 — Web app: contribution flows
- [ ] Build "suggest edit" UI on entry pages — done when logged-in user can submit edit; queued in `suggested_edits`.
- [ ] Build "suggest new entry" form — done when form validates against schema and submits.
- [ ] Build team-admin review queue UI — done when admin can approve/reject/edit each suggestion.
- [ ] Wire approval → entry insert/update + audit_log entry — done when audit table records actor + before/after.
- [ ] Email notification on suggestion outcome — done when email sent on approve/reject (configurable).
- [ ] Rate-limit suggestions per user (10/day) — done when 11th submission 429s.

## P2 — Web app: team admin
- [ ] Team dashboard page — done when admin sees entry counts, member count, recent activity.
- [ ] Team entry CRUD UI — done when admin can create/edit/delete team entries w/ live preview of merge result.
- [ ] Team member list + role management — done when admin can promote/demote/remove members.
- [ ] Domain tag management — done when admin can define team-specific domain tags.
- [ ] Team settings: default domain filter, allow public layer toggle — done when settings persist.
- [ ] Team export — done when CSV+JSON exports include all team entries w/ sources.
- [ ] Team import — done when JSON import validates and inserts w/ dedup against existing entries.

## P2 — Web app: personal layer
- [ ] Personal glossary CRUD — done when user can add private entries visible only to them.
- [ ] Personal entry priority: shadow team and public entries — done when merge prefers personal > team > public.
- [ ] Personal export — done when user can export their entries.

## P2 — Web app: public-facing pages
- [ ] About page — done when explains layered model + non-goals.
- [ ] Sources page — done when lists all public sources w/ license + last refresh timestamp.
- [ ] Pricing/hosting page (free OSS self-host + optional managed) — done when page renders w/ install CTAs.
- [ ] Install hub: links to ext, Slack, MCP, docker — done when each surface has install card.
- [ ] Status page or uptime widget for hosted — done when widget displays current status from health check.
- [ ] Privacy policy — done when page describes data handling (no query logging by default in self-host).
- [ ] Terms of service — done when page committed.

## P3 — Browser extension
- [ ] Scaffold WXT project in `extensions/browser` — done when `pnpm dev --filter @wat/ext` opens an extension-loaded Chrome.
- [ ] Define manifest v3 permissions (activeTab, storage, contextMenus, scripting) — done when manifest is minimal and lints clean.
- [ ] Implement options page — done when user can configure API base URL, account login, hover-mode toggle, domain filters.
- [ ] Implement background service worker — done when worker handles auth + API calls + caches results in `chrome.storage.local`.
- [ ] Implement content script for hover-explain — done when hovering an all-caps token shows tooltip w/ top expansion + sources.
- [ ] Implement opt-in auto-highlight of acronyms on page — done when toggle reveals subtle underline + tooltip on detected acronyms.
- [ ] Implement sidebar UI (side panel API for Chrome) — done when panel opens, mirrors web search, scoped to current page context.
- [ ] Implement context-menu "Look up in wat" on text selection — done when right-clicking selected text opens sidebar w/ result.
- [ ] Implement per-page context boost (use page title + headings as context string) — done when CAP on a k8s docs page favors Cluster Autoscaler over CAP-theorem.
- [ ] Implement account sync — done when logged-in user sees team entries in tooltips.
- [ ] Implement offline cache w/ LRU for last 500 lookups — done when offline mode returns cached entries.
- [ ] Implement telemetry-off-by-default — done when fresh install has zero outbound calls until user interacts.
- [ ] Cross-browser test on Chrome, Firefox, Edge, Brave — done when feature parity verified manually.
- [ ] Submit Chrome Web Store listing — done when listing is live (or in-review w/ assets ready: 1280x800 promo, icons, description).
- [ ] Submit Firefox add-ons listing — done when AMO listing is live or in review.
- [ ] Submit Edge add-ons listing — done when listing submitted.
- [ ] Write extension README w/ install + privacy notes — done when README committed.
- [ ] Record 30-sec demo GIF of hover-explain on a k8s docs page — done when GIF in `/docs/assets/ext-hover.gif`.

## P3 — Slack app
- [ ] Scaffold Bolt-TS project in `apps/slack` — done when local socket-mode bot connects to a dev workspace.
- [ ] Implement OAuth install flow — done when `Add to Slack` button completes install and persists tokens encrypted at rest.
- [ ] Map Slack workspace → wat team via installer email domain — done when install auto-associates workspace w/ existing team where domains match.
- [ ] Implement `/wat <term>` slash command — done when command returns ephemeral message w/ top result + disambiguation buttons.
- [ ] Implement message shortcut "Explain acronyms" — done when shortcut on a message returns ephemeral block listing detected acronyms + expansions.
- [ ] Implement @wat mention handler — done when mentioning the bot w/ a term replies in-thread.
- [ ] Implement `/wat-define <term> as <expansion>` admin command — done when admins (Slack workspace admins) can add team entries from Slack.
- [ ] Implement `/wat-suggest` for members — done when members can suggest, queued for admin review in web app.
- [ ] Implement opt-in auto-detect mode (channel setting) — done when bot posts ephemeral suggestion in channels w/ unknown-acronym usage.
- [ ] Implement rate limiting per-workspace — done when bursts >30/min throttle gracefully.
- [ ] Token storage encryption — done when tokens encrypted w/ AES-GCM via env-provided KMS key.
- [ ] Slack app icon + description assets — done when assets committed in `apps/slack/assets/`.
- [ ] Submit Slack App Directory listing — done when listing is in review w/ security questionnaire complete.
- [ ] Write Slack install README — done when README explains scopes + permissions.
- [ ] Record 30-sec demo GIF of `/wat` + message shortcut — done when GIF in `/docs/assets/slack-demo.gif`.

## P3 — MCP server
- [ ] Scaffold MCP TS server in `apps/mcp` — done when `npx @wat/mcp` connects via stdio to Claude Desktop locally.
- [ ] Implement `lookup(term, context?)` tool — done when MCP tool returns top-N typed results w/ citations.
- [ ] Implement `list_team_acronyms(domain?)` tool — done when call returns paged list of team entries.
- [ ] Implement API-key auth — done when MCP rejects calls w/o valid key; key scoped to a team.
- [ ] Publish `@wat/mcp` to npm — done when `npx @wat/mcp@latest` is installable.
- [ ] Document Claude Desktop install — done when README has working config snippet.
- [ ] Document Cursor install — done when README has working config snippet.
- [ ] Document VSCode + Continue.dev install — done when README has snippet.
- [ ] Submit to Anthropic MCP registry — done when PR opened to `modelcontextprotocol/servers`.
- [ ] Submit to Cursor's MCP catalog — done when listed or in-review.
- [ ] Record demo of Claude Desktop calling wat MCP — done when GIF in `/docs/assets/mcp-demo.gif`.

## P4 — Self-host packaging
- [ ] Write `Dockerfile` for web app — done when image builds <500MB and starts on `:3000`.
- [ ] Write `Dockerfile` for Slack app — done when image builds and runs in socket-mode + HTTP-mode.
- [ ] Write `docker-compose.yml` bundling web + slack + postgres — done when `docker compose up` boots full stack from clean machine in <5 min.
- [ ] Provide `.env.example` w/ all required vars + defaults — done when copy + edit gets a working local instance.
- [ ] Health-check endpoints `/healthz`, `/readyz` — done when compose health-checks pass.
- [ ] Backup script for Postgres + uploads — done when `scripts/backup.sh` produces a restorable tarball.
- [ ] Restore script — done when restore from tarball yields working DB on a fresh machine.
- [ ] Helm chart `charts/wat` for k8s — done when `helm install wat charts/wat` brings up stack on a kind cluster.
- [ ] Terraform module for Fly.io single-region deploy — done when `terraform apply` produces a working URL.
- [ ] Document self-host in `docs/self-host.md` — done when guide includes Docker, Helm, Fly paths.

## P4 — Hosted instance (operator-side)
- [ ] Provision hosted DB (Neon or Supabase) — done when DSN available and migrations applied.
- [ ] Deploy `apps/web` to Vercel — done when prod URL responds w/ search results.
- [ ] Deploy `apps/slack` to Railway/Fly — done when prod URL accepts Slack events.
- [ ] Configure CDN + caching — done when entry pages hit ETag/cache on second load.
- [ ] Configure rate limits via Upstash or similar — done when anonymous requests are capped per-IP.
- [ ] Configure WAF rules — done when known abusive patterns are blocked.
- [ ] Set up monitoring (Grafana Cloud / BetterStack) — done when dashboard shows req/s, p95 latency, error rate, DB CPU.
- [ ] Set up alerting on SLO breach — done when synthetic alert fires to email/Discord.
- [ ] Configure backups (daily) — done when restore drill succeeds from latest backup.
- [ ] Configure DNS + TLS — done when `https://wat.dev` resolves w/ valid cert.

## P5 — Testing
- [ ] Unit tests for `packages/core` schema + normalization — done when ≥90% line coverage in package.
- [ ] Unit tests for `packages/search` ranking + fusion — done when ≥85% coverage + benchmark regression test.
- [ ] Integration tests for `packages/db` against ephemeral Postgres (testcontainers) — done when tests pass in CI.
- [ ] E2E tests for web search UX (Playwright) — done when 10 scenarios pass headless in CI.
- [ ] E2E tests for browser extension (Playwright + WXT testing helpers) — done when hover + sidebar scenarios pass.
- [ ] Slack app integration tests w/ Bolt's test helpers — done when slash + shortcut + mention scenarios pass.
- [ ] MCP server contract tests — done when MCP-CLI test passes against `lookup` + `list_team_acronyms`.
- [ ] Load test search endpoint (k6) — done when 100 RPS sustained w/ p95 <200ms hosted.
- [ ] Chaos test for DB failover (self-host) — done when killing primary recovers within 30s via compose-level retry.
- [ ] Security tests for SQLi/XSS — done when fuzz inputs over all forms produce no SQL errors and outputs are sanitized.
- [ ] License scan via FOSSA or ScanCode — done when no license violations in dep tree.
- [ ] Dependency vulnerability scan via `pnpm audit` + Snyk — done when no high/critical vulns or all explicitly waived.

## P5 — Performance & ops
- [ ] Profile cold-start of web app — done when cold p95 <800ms on Vercel.
- [ ] Profile warm search path — done when warm p95 <80ms server-side excluding network.
- [ ] Optimize Postgres queries via EXPLAIN ANALYZE — done when no seq scans on hot paths.
- [ ] Tune ivfflat/HNSW index params — done when recall@10 ≥95% on benchmark.
- [ ] Add HTTP cache headers + ETag on entry pages — done when conditional GET returns 304.
- [ ] Add Redis cache layer for top 1000 queries (optional) — done when Redis-enabled mode reduces DB load by ≥40%.
- [ ] Implement structured rate-limiting per-user, per-IP, per-team — done when limits are configurable and tested.

## P5 — Docs & demos
- [ ] Write top-level `README.md` w/ install + screenshots — done when README renders correctly on GitHub and includes badges.
- [ ] Write `docs/architecture.md` w/ system diagram — done when diagram + text covers data flow across surfaces.
- [ ] Write `docs/contributing.md` — done when guide covers local setup, PR conventions, scraper authoring.
- [ ] Write `docs/security.md` — done when threat model + responsible disclosure are committed.
- [ ] Write `docs/api.md` — done when REST + MCP APIs are fully documented w/ examples.
- [ ] Build interactive search demo on landing page — done when anyone can search w/o login from `/`.
- [ ] Build "Try with my domain" CTA on landing — done when enter-email flow shows a teaser of team mode.
- [ ] Record 60-sec product hero video — done when MP4 committed and embedded in README.

## P6 — Launch (v0.1)
- [ ] Pick launch date — done when date is set, internal owners assigned.
- [ ] Draft Show HN title + opening comment — done when copy reviewed by 2 people.
- [ ] Prepare press kit (screenshots, GIFs, logo) — done when `press/` dir contains assets.
- [ ] Set up @watdev or similar handles on X / Bluesky / Mastodon — done when accounts exist w/ bio + pinned post draft.
- [ ] Pre-launch beta: invite 20 friendly testers — done when ≥10 testers report back issues fixed.
- [ ] Submit to Hacker News — done when Show HN post is live.
- [ ] Submit to r/programming — done when post is live.
- [ ] Submit to r/devops, r/sysadmin, r/cscareerquestions — done when each post is live.
- [ ] Submit to Lobsters — done when post is live (invited).
- [ ] Submit to Product Hunt — done when listing is live.
- [ ] Submit to Hacker News Newsletter / TLDR Dev / Pointer — done when at least one accepts.
- [ ] Post in Slack community directories (r/Slack, Slack Subreddit) — done when posts are live.
- [ ] Post in MCP community channels (Anthropic Discord, Cursor Discord) — done when posts are live.
- [ ] Monitor HN comments + reply within 30 min during peak window — done when launch-day playbook is followed (Tue-Thu 9AM-12PM ET).
- [ ] Track launch metrics: stars, installs, Slack installs, MCP installs — done when dashboard committed and updated daily for 2 weeks.

## P7 — Phase 2 (post-launch)
- [ ] Team-doc scraping: Notion connector — done when authenticated user can import a Notion DB of acronyms w/ source links.
- [ ] Team-doc scraping: Confluence connector — done when same.
- [ ] Team-doc scraping: Linear connector (team-level glossary lives in Linear docs) — done when same.
- [ ] Team-doc scraping: GitHub Wiki + repo `GLOSSARY.md` connector — done when same.
- [ ] Team-doc scraping: Google Docs connector — done when same.
- [ ] Acronym extraction from team docs via LLM (cited, not hallucinated) — done when extractor produces entries flagged "needs review" w/ doc-source citation.
- [ ] Team-side embeddings: per-team domain-fine-tuned embedding option — done when team can opt to re-embed its overlay w/ a chosen model.
- [ ] Optional self-hosted ollama/llama.cpp adapter for context inference — done when self-hosters can run w/o cloud calls.
- [ ] Browser ext: PDF support — done when hovering acronyms in PDFs.js viewer works.
- [ ] Browser ext: in-page acronym density heatmap — done when toggling shows visual density indicator per paragraph.
- [ ] Slack: huddle support / channel digest of unknown acronyms — done when a weekly digest posts.
- [ ] Slack: workspace admin dashboard — done when admins can see top-queried acronyms + gaps.
- [ ] MCP: write tool (suggest definition) gated by team policy — done when agents can propose entries.
- [ ] LSP server for Neovim/VSCode hovers (optional) — done when LSP returns hover content for selected token.
- [ ] Mobile-friendly PWA polish — done when Lighthouse PWA score ≥90.
- [ ] Public API w/ token + rate limits — done when third-parties can use the lookup endpoint w/ a quota.
- [ ] Webhook subscriptions (new entry, edited entry) for team integrations — done when test webhook receives signed payload.

## P7 — Community & moat
- [ ] Set up GitHub Discussions — done when categories exist + welcome post pinned.
- [ ] Set up Discord or Matrix channel — done when invite link in README.
- [ ] Publish monthly stats post (corpus growth, top queries by domain) — done when first post is live.
- [ ] Identify and contact 5 large OSS communities to seed team layers (Kubernetes, Rust, Postgres, Linux, CNCF) — done when at least one accepts a team-owned glossary.
- [ ] Author 3 launch blog posts: (1) "wat: layered glossary for tech jargon", (2) "Hybrid search w/ Postgres alone", (3) "Designing an MCP server for context-aware lookup" — done when posts published on dev.to/Medium/personal blog.
- [ ] Submit talk proposal to a small conf (eg. local meetup, MCP Summit) — done when proposal submitted.

## P8 — Maintenance & long-haul
- [ ] Define SLO: 99.5% uptime hosted, <500ms p95 — done when SLO doc committed.
- [ ] Document on-call playbook — done when runbook covers DB failover, scraper failure, abuse mitigation.
- [ ] Rotate API keys + tokens quarterly — done when calendar reminder + rotation script exist.
- [ ] Quarterly license audit on corpus — done when audit log committed.
- [ ] Track corpus quality KPI — done when monthly report committed (hit-rate, drift, source coverage).
- [ ] Track surface adoption KPI — done when monthly report committed (web MAU, ext installs, Slack installs, MCP installs).

## Acceptance gates (must pass before declaring v0.1)
- [ ] Hybrid search hit-rate ≥90% on top-1, ≥98% on top-5 — verified by `pnpm bench`.
- [ ] Hosted p95 search <150ms — verified by k6 run.
- [ ] Self-host p95 search <300ms on 2-core — verified by k6 run on docker compose.
- [ ] `docker compose up` on a clean machine boots in <5 min — verified on 2 OSes.
- [ ] Zero fabricated definitions in benchmark — verified by source-coverage check.
- [ ] Browser ext + Slack app + MCP server all functional against same hosted instance — verified by E2E suite.
- [ ] All public-corpus entries have source URLs + license tags — verified by linter.
- [ ] CI green on `main` for 7 consecutive days — verified by GH Actions history.

## Folder/root note
Rename folder freely; keep `idea.md` and `todo.md` at project root.
