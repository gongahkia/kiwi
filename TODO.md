# wat — Todo

Format: `- [ ] task — done when <condition>`. Phases run roughly in order; tasks within a phase can parallelize unless noted.

## Non-goals reminder
- No AI-only unsourced definitions. Every result cites or is marked unsourced.
- No general English dictionary. Tech terms only — acronyms + concepts + systems (scope expanded 2026-06-23). Not words like "schedule" or "approval".
- No required external API for lookup. Self-host == fully usable.
- No CLI surface, no satire/shame tone, no brainrot/Gen-Z slang mode, no meeting-mic "panic button" surface, no Pi constraint.

## P0 — Repo & schema foundation
- [ ] Reserve npm scope `@wat` — done when `npm view @wat/core` returns 404 → publish placeholder.
- [ ] Reserve domain candidates — done when at least two of `wat.dev`, `getwat.dev`, `wat.tools` are availability-checked and one secured.
- [ ] Reserve GitHub org `wat` or fallback — done when org exists and repo `wat/wat` is created.
- [ ] Set up GitHub Actions CI matrix (lint, typecheck, test, build) — done when CI green on `main` w/ all jobs.

## P0 — Database & migrations

## P0 — Core package

## P1 — Search engine
- [ ] Measure search latency on hosted (Vercel + Neon) — done when p95 < 150ms for 1k-warmup queries.

## P1 — Public corpus ingestion framework

## P1 — Public corpus scrapers (one task per source)

## P1 — Corpus quality controls

## P2 — Web app foundation
- [ ] Add Google OAuth provider — done when Google login produces a session.
- [ ] Add Slack OAuth provider — done when Slack login produces a session.
- [ ] Add Sentry or self-host error tracking — done when a thrown error in prod surfaces in dashboard.

## P2 — Web app: search UX

## P2 — Web app: contribution flows

## P2 — Web app: team admin

## P2 — Web app: personal layer

## P2 — Web app: public-facing pages

## P3 — Browser extension
- [ ] Cross-browser test on Chrome, Firefox, Edge, Brave — done when feature parity verified manually.
- [ ] Submit Chrome Web Store listing — done when listing is live (or in-review w/ assets ready: 1280x800 promo, icons, description).
- [ ] Submit Firefox add-ons listing — done when AMO listing is live or in review.
- [ ] Submit Edge add-ons listing — done when listing submitted.
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
- [ ] Submit Slack App Directory listing — done when listing is in review w/ security questionnaire complete.
- [ ] Record 30-sec demo GIF of `/wat` + message shortcut — done when GIF in `/docs/assets/slack-demo.gif`.

## P3 — MCP server
- [ ] Scaffold MCP TS server in `apps/mcp` — done when `npx @wat/mcp` connects via stdio to Claude Desktop locally.
- [ ] Publish `@wat/mcp` to npm — done when `npx @wat/mcp@latest` is installable.
- [ ] Submit to Anthropic MCP registry — done when PR opened to `modelcontextprotocol/servers`.
- [ ] Submit to Cursor's MCP catalog — done when listed or in-review.
- [ ] Record demo of Claude Desktop calling wat MCP — done when GIF in `/docs/assets/mcp-demo.gif`.

## P4 — Self-host packaging
- [ ] Terraform module for Fly.io single-region deploy — done when `terraform apply` produces a working URL.

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
- [ ] Integration tests for `packages/db` against ephemeral Postgres (testcontainers) — done when tests pass in CI.
- [ ] E2E tests for web search UX (Playwright) — done when 10 scenarios pass headless in CI.
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
- [ ] Add Redis cache layer for top 1000 queries (optional) — done when Redis-enabled mode reduces DB load by ≥40%.

## P5 — Docs & demos
- [ ] Record 60-sec product hero video — done when MP4 committed and embedded in README.

## P6 — Launch (v0.1)
- [ ] Pick launch date — done when date is set, internal owners assigned.
- [ ] Draft Show HN title + opening comment — done when copy reviewed by 2 people.
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
- [ ] Mobile-friendly PWA polish — done when Lighthouse PWA score ≥90.
- [ ] Webhook subscriptions (new entry, edited entry) for team integrations — done when test webhook receives signed payload.

## P7 — Community & moat
- [ ] Set up GitHub Discussions — done when categories exist + welcome post pinned.
- [ ] Set up Discord or Matrix channel — done when invite link in README.
- [ ] Publish monthly stats post (corpus growth, top queries by domain) — done when first post is live.
- [ ] Identify and contact 5 large OSS communities to seed team layers (Kubernetes, Rust, Postgres, Linux, CNCF) — done when at least one accepts a team-owned glossary.
- [ ] Author 3 launch blog posts: (1) "wat: layered glossary for tech jargon", (2) "Hybrid search w/ Postgres alone", (3) "Designing an MCP server for context-aware lookup" — done when posts published on dev.to/Medium/personal blog.
- [ ] Submit talk proposal to a small conf (eg. local meetup, MCP Summit) — done when proposal submitted.

## P8 — Maintenance & long-haul

## Acceptance gates (must pass before declaring v0.1)
- [ ] Hybrid search hit-rate ≥90% on top-1, ≥98% on top-5 — verified by `pnpm bench`.
- [ ] Hosted p95 search <150ms — verified by k6 run.
- [ ] Self-host p95 search <300ms on 2-core — verified by k6 run on docker compose.
- [ ] `docker compose up` on a clean machine boots in <5 min — verified on 2 OSes.
- [ ] Zero fabricated definitions in benchmark — verified by source-coverage check.
- [ ] Browser ext + Slack app + MCP server all functional against same hosted instance — verified by E2E suite.
- [ ] CI green on `main` for 7 consecutive days — verified by GH Actions history.

## Audit backlog — team adoption readiness (2026-06-20)

### P0 — Stop data loss and make Postgres the product source of truth
- [ ] Replace in-memory team entry store with Postgres-backed repository — done when `apps/web/src/lib/team-entries.ts` reads/writes `team_entries`, `team_entry_sources`, and related rows, survives process restart, and all existing team-entry tests run against an isolated test DB.
- [ ] Replace in-memory personal entry store with Postgres-backed repository — done when personal entries persist across restart, are scoped by authenticated `user_id`, and personal export/import tests prove user A cannot read user B entries.
- [ ] Replace in-memory suggestion queue with Postgres-backed repository — done when `/suggest/api` and `/team/admin/review/api` persist suggested edits in `suggested_edits` and pending suggestions survive redeploy.
- [ ] Replace in-memory audit log with Postgres-backed repository — done when every create/update/delete/approve/import action writes `audit_log` rows and admin audit UI reads from DB.
- [ ] Replace in-memory team settings with Postgres-backed repository — done when settings are stored per `team_id` in `teams.settings_jsonb` or a dedicated table and persist across restart.
- [ ] Replace in-memory rate limiter for hosted mode — done when rate limits use Redis/Upstash/Postgres advisory storage in production and still support an in-memory dev fallback.
- [ ] Add DB repository interfaces for public, team, and personal entries — done when web/API/search code depends on typed repositories instead of module-level arrays or seed JSON reads.
- [ ] Migrate team entry source model to match glossary source schema — done when team/personal entries store source quality, title, URL, publisher, license, retrieved date, and snippet in normalized DB rows.
- [ ] Add idempotent migration runner for app startup or release phase — done when a clean deploy can run migrations exactly once without manual `pnpm db:migrate` steps.
- [ ] Add idempotent public corpus seed/import job — done when a clean DB can import checked-in corpus data without duplicates and without deleting team/personal overlays.
- [ ] Update Docker Compose to apply migrations and seed public corpus automatically — done when `docker compose up --build` yields a searchable DB-backed app on a clean machine.
- [ ] Make `/readyz` verify database connectivity and migration state — done when readiness fails if DB is unavailable, migrations are missing, or seed corpus is absent.
- [ ] Add restart persistence smoke test — done when an E2E creates a team entry, restarts web, and confirms the entry is still searchable.
- [ ] Add multi-instance persistence smoke test — done when two web processes behind the same DB can create/read the same team and personal entries.

### P0 — Unify authentication and authorization
- [ ] Replace custom `wat_session` authorization with NextAuth session resolution — done when middleware and route handlers use NextAuth session/user/team data and `wat_session` is removed except test-only fixtures.
- [ ] Add shared server auth helper — done when every protected route calls one helper that returns `{ userId, teamId, role }` or throws typed unauthorized/forbidden errors.
- [ ] Protect personal APIs with authenticated user sessions — done when `/personal/api` and personal exports reject unauthenticated requests and only use the session user ID.
- [ ] Protect team admin APIs with team admin role checks in route handlers — done when `/team/admin/*/api` cannot be called directly by non-admins even if middleware is bypassed.
- [ ] Protect suggestion review APIs with team admin role checks — done when only admins for the target team can approve/reject suggestions.
- [ ] Scope all team reads and writes by `team_id` — done when team entries, members, settings, imports, exports, suggestions, and audit logs always filter by authenticated team.
- [ ] Add tenant isolation integration tests — done when tests prove team A cannot list/search/export/update/delete team B data through web APIs, browser extension API calls, Slack, or MCP.
- [ ] Add per-team API key table — done when API keys are hashed at rest, scoped to one team, optionally one user, and can be created/revoked/rotated by team admins.
- [ ] Replace global `WAT_API_KEY` for hosted multi-tenant traffic — done when production API calls authenticate via DB-backed per-team keys and global `WAT_API_KEY` is only a self-host/dev escape hatch.
- [ ] Add API key scopes — done when keys can be read-only, suggestion-write, team-entry-write, or admin, and endpoints enforce those scopes.
- [ ] Add API key management UI — done when admins can create, name, copy once, revoke, and rotate team API keys from the web app.
- [ ] Add API key last-used metadata — done when key usage stores last-used time, actor, IP hash, and surface without logging raw keys.
- [ ] Add email-domain team claim flow — done when first verified user for a domain can claim/create a team and later users with same domain join as members by default.
- [ ] Add public-email-domain guardrail — done when gmail.com/outlook.com/yahoo.com/etc. do not auto-create shared teams without explicit invite or manual approval.
- [ ] Add admin recovery path — done when a team with no admins can recover ownership through a documented, audited process.

### P0 — Make multi-tenant search real
- [ ] Switch web search API to DB-backed merged search — done when `/api/v1/search` reads public, team, and personal entries from Postgres for the authenticated identity.
- [ ] Preserve layer priority in DB-backed search — done when identical terms rank personal > team > public for scoped users and tests cover collisions.
- [ ] Add team/private entries to web search UI for signed-in users — done when the homepage search includes scoped personal/team overlays, not only public seed entries.
- [ ] Add context/domain boosting for DB-backed team and personal entries — done when `context` boosts matching domains across all layers and tests cover browser page hostname context.
- [ ] Add no-result suggestion flow tied to authenticated team — done when no-match searches can create scoped suggestions without leaking query text across teams.
- [ ] Add search result provenance for user-contributed entries — done when team/personal results clearly show user/team-contributed confidence and source status.
- [ ] Add DB search performance indexes for team/personal tables — done when EXPLAIN plans use FTS/trigram indexes and p95 stays under target with public + team overlays.
- [ ] Add search analytics with privacy-safe aggregation — done when query hashes, layer hits, confidence distribution, and latency are captured without raw private query logging.

### P0 — Security and privacy blockers before private team data
- [ ] Remove wildcard CORS from production API responses — done when allowed origins are configurable per deployment/team and browser extension origins are explicitly allowed.
- [ ] Add CSRF protection or strict same-origin handling for cookie-authenticated mutations — done when web form/API mutations cannot be triggered cross-site by an attacker.
- [ ] Add Slack request signature verification — done when `/slack/events` rejects unsigned or replayed Slack requests.
- [ ] Encrypt OAuth tokens and bot tokens at rest — done when Slack/Google/other OAuth tokens use envelope encryption or `SLACK_TOKEN_ENCRYPTION_KEY` equivalent with rotation docs.
- [ ] Add source/license validation for custom team entries — done when public-corpus rules remain strict and private entries cannot accidentally claim public-compatible provenance unless provided.
- [ ] Add audit entries for API key and integration changes — done when key creation/revocation, Slack install, extension token creation, imports, and member role changes are audited.
- [ ] Add private-data-safe logging policy enforcement — done when logs never include raw private definitions, raw queries for authenticated teams, API keys, cookies, OAuth tokens, or magic links.
- [ ] Add XSS regression tests for all user-provided glossary fields — done when term, expansion, meaning, source title, source snippet, and domains are rendered escaped across web/extension/Slack.
- [ ] Add SQL injection regression tests for all DB-backed filters and forms — done when fuzzed strings do not produce SQL errors or cross-tenant reads.
- [ ] Add abuse controls for write endpoints — done when suggestions, imports, custom-entry saves, and Slack writes have per-user/team/IP limits and actionable 429 responses.
- [ ] Add security headers — done when production responses include CSP, HSTS where appropriate, frame protections, content-type options, and referrer policy.
- [ ] Add responsible disclosure contact to README and security docs — done when users can privately report vulnerabilities without opening a public exploit issue.

### P1 — Team onboarding and admin usability
- [ ] Build first-run team onboarding flow — done when a new user can create or join a team, set team name/domain, and land on an admin checklist.
- [ ] Build member invitation flow — done when admins can invite users by email, pending invites expire, and accepted invites create scoped team membership.
- [ ] Build member role management backed by DB — done when admins can promote/demote/remove members and all changes persist/audit.
- [ ] Build team settings page backed by DB — done when default domain filters, public-layer toggle, and domain tags are team-specific and durable.
- [ ] Add team import UI for JSON and CSV — done when admins can upload glossary files, preview validation errors, and import accepted rows.
- [ ] Add import dry-run and conflict resolution — done when duplicate term/expansion conflicts show create/update/skip choices before commit.
- [ ] Add export UI for JSON and CSV backed by DB — done when admins can export only their team entries with sources and audit metadata.
- [ ] Add bulk edit/delete safeguards — done when destructive bulk actions require confirmation and write audit rows.
- [ ] Add team glossary dashboard — done when admins see total entries, pending suggestions, top searched acronyms, no-result gaps, stale entries, and source coverage.
- [ ] Add entry validation messages in CRUD forms — done when invalid source URLs, missing fields, duplicate IDs, and duplicate term/expansion pairs show inline errors.
- [ ] Add generated IDs for manual entries — done when users do not have to invent stable IDs while creating entries in the UI.
- [ ] Add clear confidence/layer labels for team users — done when users understand whether a result is public, team, personal, pending, or low-confidence.
- [ ] Add no-result CTA to create/suggest an acronym — done when failed searches can flow directly into personal save or team suggestion.

### P1 — Browser extension adoption blockers
- [ ] Add extension login/pairing flow — done when a user can connect the extension to their wat account without manually pasting API URL, email, token, and team ID.
- [ ] Add extension team picker — done when users in multiple teams can choose the active team and the extension sends the right team scope.
- [ ] Add extension custom-entry save E2E test — done when selecting page text, saving a custom acronym, and finding it in later lookup is covered headlessly.
- [ ] Add extension conflict handling for saved acronyms — done when saving an existing term shows update/keep both/cancel choices instead of a raw 409.
- [ ] Add extension save-source preview — done when users see the page URL/title that will be attached before saving.
- [ ] Add extension offline/error states — done when failed lookup/save distinguishes offline, unauthorized, forbidden, rate-limited, and validation errors.
- [ ] Add extension privacy mode review — done when hover/highlight behavior is documented and verified to send only tokens/context, not full page contents by default.
- [ ] Add extension settings validation — done when invalid API URLs/tokens show a test-connection failure before save.
- [ ] Add extension release assets — done when required icons, screenshots, short/long descriptions, and privacy copy are committed.
- [ ] Publish signed browser extension builds — done when Chrome, Firefox, and Edge users can install without developer mode.
- [ ] Add enterprise extension deployment docs — done when a team admin can deploy via Chrome Enterprise/Edge policy with preconfigured API URL.

### P1 — Slack adoption blockers
- [ ] Replace Slack HTTP scaffold with real Bolt runtime wiring — done when the deployed Slack app receives commands/events and dispatches registered wat handlers.
- [ ] Implement Slack OAuth install callback — done when `Add to Slack` completes, verifies state, and stores workspace/team install data.
- [ ] Persist Slack workspace installs in DB — done when bot/user tokens, workspace ID, team mapping, installer, scopes, and timestamps survive restart.
- [ ] Map Slack workspace to wat team securely — done when installer identity/domain maps to an existing or new wat team with admin review for ambiguous cases.
- [ ] Enforce Slack admin + wat admin for `/wat-define` — done when a Slack workspace admin who is not a wat team admin cannot write team entries.
- [ ] Send Slack API auth headers to wat API — done when Slack lookup/write requests use scoped per-team credentials rather than anonymous/global calls.
- [ ] Implement `/wat` command in deployed Slack app — done when a real Slack workspace command returns sourced ephemeral results from the same hosted API as web.
- [ ] Implement `/wat-define` against DB-backed team entries — done when approved Slack definitions appear in web search/admin and audit logs.
- [ ] Implement `/wat-suggest` against DB-backed suggestion queue — done when member suggestions appear in web review queue.
- [ ] Implement message shortcut against selected message only — done when explicit shortcuts parse acronyms from the selected payload and do not ingest channel history.
- [ ] Add Slack workspace/channel rate limits backed by durable store — done when command bursts are throttled per workspace/channel/user.
- [ ] Add Slack install/remove lifecycle handling — done when app uninstall revokes tokens and disables workspace integration without deleting glossary data.
- [ ] Add Slack E2E or contract tests — done when command, shortcut, mention, install, signature verification, and rate-limit paths are tested.
- [ ] Prepare Slack App Directory submission — done when security questionnaire, scopes, privacy notes, screenshots, and demo GIF are ready.

### P1 — MCP adoption blockers
- [ ] Back MCP lookup with hosted/API or DB repositories instead of dev fixtures — done when MCP returns the same scoped public/team entries as web for the same API key.
- [ ] Replace MCP file-backed suggestions with DB-backed suggestions — done when `suggest_definition` queues suggestions in the same review UI as web/Slack.
- [ ] Add MCP per-team API key support — done when MCP auth uses DB-backed scoped keys and returns clear unauthorized/forbidden errors.
- [ ] Publish `@wat/mcp` package — done when users can run `npx @wat/mcp@latest` without cloning the repo.
- [ ] Add MCP hosted configuration docs — done when Claude Desktop/Cursor examples show hosted URL, key scopes, team ID behavior, and self-host mode.
- [ ] Add MCP integration tests against a running web API — done when lookup/list/suggest are verified against seeded DB fixtures.
- [ ] Submit MCP catalog listings — done when Anthropic/Cursor listing PRs or submissions are opened with screenshots and docs.

### P1 — Public corpus coverage and ingestion readiness
- [ ] Import scraper outputs into production-searchable corpus — done when daily corpus refresh deltas can be reviewed, merged, and loaded into the DB-backed public search index.
- [ ] Increase seed/public corpus beyond demo size — done when public search covers at least the target launch benchmark set and no longer relies on ~50 unique seed terms.
- [ ] Add corpus source inventory page — done when docs/UI list each source, license policy, last refresh time, entry count, and failure status.
- [ ] Add corpus refresh dashboard/report — done when scheduled scraper runs publish added/changed/removed counts, license changes, parser errors, and benchmark impact.
- [ ] Add bad-delta rollback path — done when a bad corpus import can be reverted to a known-good version with documented commands.
- [ ] Add source license change alerts — done when changes in source license metadata block automatic import until reviewed.
- [ ] Add benchmark set for ambiguous acronyms — done when CAP/API/ACL/etc. have expected domain-aware rankings and regressions fail CI.
- [ ] Add no-fabrication corpus gate — done when entries without acceptable provenance are excluded from public results or marked review-only.
- [ ] Add corpus quality sampling workflow — done when each refresh PR includes random sample entries for human review.

### P1 — API readiness for teams and integrations
- [ ] Document `POST /api/v1/custom-entries` — done when API docs include request/response schemas, auth, scopes, CORS behavior, errors, and examples.
- [ ] Add OpenAPI spec for REST endpoints — done when search, custom entries, suggestions, imports, exports, keys, and team admin endpoints are machine-readable.
- [ ] Standardize REST error shapes — done when all APIs return consistent `{ error, code, message, request_id }` style responses.
- [ ] Add pagination to list/export APIs where needed — done when large teams can list entries, audit logs, and suggestions without loading all rows.
- [ ] Add import API authentication and team scoping — done when bulk imports require admin/key scope and cannot affect other teams.
- [ ] Add custom-entry update/upsert mode — done when integrations can intentionally update an existing acronym without relying on generated IDs.
- [ ] Add API examples for curl, browser extension, Slack, and MCP — done when docs show minimal working authenticated requests for each surface.
- [ ] Add request IDs to all API responses and logs — done when support can correlate user-visible errors to server logs.

### P1 — Self-host and deployment usability
- [ ] Create one-command local demo path — done when a new developer can run one documented command and get web search, DB, seeded corpus, and Mailpit working.
- [ ] Create one-command production-ish self-host path — done when Docker Compose with `.env` boots web + DB + migrations + seed + health checks without manual commands.
- [ ] Add `.env` validation at startup — done when missing/unsafe production secrets fail fast with actionable messages.
- [ ] Add generated secrets helper — done when docs/scripts help self-hosters generate `AUTH_SECRET`, API key seed, and token encryption keys.
- [ ] Add backup and restore scripts to Compose docs — done when a self-hoster can run backup, restore to a new DB, and verify search works.
- [ ] Add Helm chart values for auth/secrets/ingress/Postgres — done when chart install works with external Postgres and documented secret refs.
- [ ] Add Fly.io deployment smoke test — done when Terraform output URL passes `/readyz` and `GET /api/v1/search?q=API`.
- [ ] Add production readiness checklist — done when docs state required secrets, DB extensions, migrations, backups, TLS, rate limits, and monitoring.
- [ ] Add clean-machine install test to CI or release process — done when Compose is verified on a fresh Linux runner before releases.

### P1 — Hosted service operations
- [ ] Provision hosted Postgres with pg_trgm and pgvector — done when migrations run and DB health is monitored.
- [ ] Deploy hosted web instance with DB-backed search — done when production URL returns public search results and scoped team results for a test team.
- [ ] Add production monitoring dashboard — done when request rate, errors, latency, DB connections, DB CPU, queue/import failures, and scraper failures are visible.
- [ ] Add alerting for availability and data-path failures — done when `/readyz`, search latency, DB errors, Slack event failures, and corpus refresh failures alert maintainers.
- [ ] Add scheduled backup verification — done when latest backup is restored in a drill and verified at least monthly.
- [ ] Add deploy rollback procedure — done when a bad web/API deploy can be rolled back without data loss and the runbook documents it.
- [ ] Add WAF/basic abuse rules — done when obvious SQLi/XSS probes and abusive request patterns are blocked or rate-limited at the edge.

### P2 — Product UX gaps that will block normal teams
- [ ] Add guided install page for each surface — done when web, extension, Slack, MCP, and API install steps are separated by role and environment.
- [ ] Add admin checklist after team creation — done when admins see next steps for importing acronyms, inviting members, installing extension, and connecting Slack.
- [ ] Add sample team glossary import template — done when CSV/JSON templates can be downloaded and imported successfully.
- [ ] Add onboarding empty states — done when empty team glossary, no suggestions, no members, and no API keys pages explain what to do next.
- [ ] Add no-results learning loop — done when no-result searches can be converted into suggestions/personal entries and later reviewed.
- [ ] Add duplicate/ambiguous acronym UX — done when users can see and choose among multiple expansions by domain/layer/confidence.
- [ ] Add stale-entry review workflow — done when entries can be marked stale/needs review and admins can update or deprecate them.
- [ ] Add deprecation support for team/personal entries — done when deprecated entries remain auditable but are hidden or labeled in normal search.
- [ ] Add user-facing privacy explanations — done when extension, Slack, MCP, and web describe exactly what text is sent and stored.

### P2 — Testing gates for credible beta
- [ ] Add full team onboarding E2E — done when Playwright covers sign up, create team, invite member, add entry, search entry, export entry.
- [ ] Add browser extension authenticated save/search E2E — done when extension pairs with a test account, saves selected text, and lookup returns personal/team layer.
- [ ] Add Slack installed-workspace E2E/fixture test — done when a simulated Slack command writes/reads scoped team data through the deployed API path.
- [ ] Add MCP hosted API E2E — done when Claude/Cursor-compatible server calls lookup/list/suggest against a test hosted API.
- [ ] Add tenant isolation test suite — done when every team/personal endpoint has positive same-tenant and negative cross-tenant cases.
- [ ] Add persistence test suite — done when restart/redeploy does not lose entries, suggestions, settings, keys, audit logs, or installs.
- [ ] Add migration compatibility test — done when migrations apply from empty DB and from previous release snapshots.
- [ ] Add import/export round-trip tests — done when exported team glossary can be imported into a new team without loss of required fields.
- [ ] Add load test with team overlays — done when benchmark includes public corpus plus at least 10k team entries and meets p95 targets.
- [ ] Add browser cross-compat release test checklist to CI artifacts — done when Chrome/Firefox/Edge/Brave results are recorded for each extension release.

### P2 — Documentation gaps that will cause failed adoption
- [ ] Rewrite README around current maturity and install paths — done when README clearly distinguishes demo, self-host, hosted beta, extension, Slack, and MCP readiness.
- [ ] Add honest limitations page — done when docs list unsupported/experimental areas: hosted auth, persistence status, extension store status, Slack status, MCP status, and corpus coverage.
- [ ] Add team admin guide — done when admins can follow docs to create a team, import entries, manage members, issue keys, and review suggestions.
- [ ] Add developer architecture guide for DB-backed layers — done when contributors can see how public/team/personal entries flow from DB to search and surfaces.
- [ ] Add security model docs for tenants and keys — done when docs explain tenant isolation, key scopes, Slack permissions, extension privacy, and audit logs.
- [ ] Add migration/runbook docs for self-hosters — done when self-hosters can upgrade versions, run migrations, back up, restore, and rollback.
- [ ] Add troubleshooting docs — done when common failures such as missing DB extensions, email login failures, extension auth failures, Slack signature errors, and no search results have fixes.

### Beta readiness acceptance gates from audit
- [ ] New-team time-to-value ≤15 minutes — verified when a fresh team can sign up, create/import an acronym, install/connect the extension, and see a scoped lookup in under 15 minutes without maintainer help.
- [ ] No in-memory product-critical state in production — verified when entries, suggestions, settings, audit logs, installs, API keys, and rate limits survive restart/redeploy.
- [ ] Auth/session model is single-source — verified when NextAuth or the chosen auth system owns all user/team identity and no production path depends on `wat_session`.
- [ ] Tenant isolation proven — verified when automated tests cover cross-team denial for every private read/write path.
- [ ] Browser extension install is non-developer-mode — verified when at least one signed store or enterprise-install path works with documented auth.
- [ ] Same hosted instance powers web, extension, Slack, and MCP — verified when all four surfaces read the same DB-backed public/team/personal data for a test team.
- [ ] Private glossary legal/privacy defaults are safe — verified when private entries are not mislabeled as open-source/public and privacy docs match actual data flows.
- [ ] Self-host clean install works — verified when `docker compose up --build` on a clean machine runs migrations, seeds corpus, and passes `/readyz` plus a search smoke test.

## Scope expansion — tech terms + contemporaries (2026-06-23)

Context for any coding agent picking up these tasks (read this before touching code):
- Decision: wat repositions from "acronym glossary" to "tech term decoder" covering acronyms (RBAC), concepts (hosting, idempotency, eventual consistency), and systems/products (Azure, Kubernetes, Kafka). Not a general English dictionary. Origin: friend feedback that the project needs to cover unfamiliar concepts/systems thrown around in senior-dev meetings, not just acronyms.
- New first-class field: `contemporaries` — peer alternatives ("this is like X but..."). Distinct from existing `related_terms` (adjacent concepts: Kubernetes→pods, kubelet). Contemporaries are competitors/substitutes (Kubernetes→Docker Swarm, Nomad, ECS). Field rendered as a one-line "Alternatives" block across all surfaces.
- Skipped intentionally (locked decisions, do NOT re-open without explicit signal):
  - Meeting-mic "panic button" surface. Rationale: real-time STT (Whisper) + privacy review + always-on mic UX is multi-month effort; same lookup moment is covered by the browser ext sidebar + Slack message-shortcut today.
  - Brainrot / Gen-Z slang explainer mode. Rationale: hard conflict w/ existing non-goal "no satire/shame tone"; viral upside doesn't outweigh dilution of rigor positioning. Marketing-only Gen-Z content (separate from product) is unblocked.
- Closest competitor surveyed: GlossaryTech (Chrome ext, recruiter-focused, closed-source, no team layer, no Slack/MCP, no contemporaries) — confirms multi-surface + contemporaries combination is differentiated.
- Reference file paths the coding agent will edit (do not invent new ones — these exist):
  - `packages/db/src/schema.ts` (Drizzle tables)
  - `packages/db/drizzle/` (new SQL migration, next number is `0016_*.sql`)
  - `packages/db/src/schema.integration.test.ts`
  - `packages/core/src/schema.ts` (Zod `GlossaryEntrySchema`)
  - `packages/core/src/entry-validator.ts`
  - `packages/core/src/merge.ts`
  - `packages/core/src/normalize.ts`
  - `packages/ingest/src/transform.ts`, `sanity.ts`, `scrapers/`
  - `data/deltas/<date>/*.json` (corpus deltas; existing fields shown in `data/deltas/2026-06-19/example.json`)
  - `docs/db-schema.md` (must be kept in sync w/ Drizzle schema)

### P1 — Corpus expansion: tech concepts + systems sources
Goal: seed corpus w/ tech concepts (hosting, idempotency, service mesh) + systems/products (cloud services, CNCF projects, Postgres extensions), not just acronyms.
- [ ] Add Wikipedia "Outline of computer science" + "Glossary of computer science" + "Outline of computing" scraper in `packages/ingest/src/scrapers/wikipedia-outline.ts` — done when scraper produces ≥ 1000 concept entries w/ Wikipedia citation per row. License: CC-BY-SA-4.0 (verify current page footers; the older 3.0 dual-license applies to historical revisions only). Mark `source_quality: "secondary"`.
- [ ] Extend existing `cncf-glossary` scraper (`packages/ingest/src/scrapers/cncf-glossary.ts`) to capture concept-type entries (eg "Cloud Native", "Service Mesh") in addition to terms — done when concept entries appear w/ confidence T1 and domain `cloud native`.
- [ ] Add MDN "Web technology for developers" concept index scraper (separate from existing MDN glossary scraper) — done when entries like "REST", "WebSocket", "Service Worker" land w/ MDN citation. License: CC-BY-SA-2.5.
- [ ] Add CNCF Landscape scraper (`packages/ingest/src/scrapers/cncf-landscape.ts`) sourcing from `cncf/landscape` repo (Apache-2.0) — done when major CNCF projects (Kubernetes, Istio, Envoy, Linkerd, Prometheus, Grafana, etcd, containerd, Helm, Argo) land as system entries. Use landscape category metadata to crosslink contemporaries within categories (eg "service mesh" category → all members are contemporaries of each other).
- [ ] Cross-map AWS↔Azure↔GCP service catalogs into contemporaries on existing entries — done when ≥ 80% of cloud service entries have ≥ 1 contemporary populated. Source of truth: GCP's published comparison `https://docs.cloud.google.com/docs/get-started/aws-azure-gcp-service-comparison` (table mapping ~150 services). Scraper lives at `packages/ingest/src/scrapers/cloud-service-comparison.ts`; emits a delta that patches existing AWS/Azure/GCP service entries w/ contemporaries arrays.
- [ ] Add Postgres extensions registry scraper — done when entries for `pg_trgm`, `pgvector`, `PostGIS`, `TimescaleDB`, `pg_partman`, `pg_stat_statements` land w/ contemporaries crosslinks where applicable (TimescaleDB↔Citus, PostGIS standalone).

### P1 — Contemporaries seed pass (manual curation)
- [ ] Curate contemporaries for top-200 most-likely-searched concepts/systems in a single committed JSON delta at `data/deltas/2026-06-23/contemporaries-seed.json` — done when file contains 200 entries each w/ a `contemporaries` array of 2–6 peer alternatives. Examples that MUST be seeded: Kubernetes→{Docker Swarm, Nomad, ECS}; Kafka→{RabbitMQ, NATS, Redpanda, Pulsar}; Redis→{Memcached, KeyDB, DragonflyDB}; Postgres→{MySQL, MariaDB, CockroachDB, YugabyteDB}; Terraform→{Pulumi, OpenTofu, CloudFormation}; Datadog→{New Relic, Grafana Cloud, Honeycomb, Splunk}; Sentry→{Bugsnag, Rollbar, Honeybadger}; OAuth→{SAML, OIDC}; gRPC→{REST, GraphQL, JSON-RPC, Thrift}; Docker→{Podman, containerd, CRI-O}; Nginx→{Apache HTTPD, Caddy, HAProxy, Traefik}; Webpack→{Vite, esbuild, Rollup, Parcel, Turbopack}; React→{Vue, Svelte, Solid, Angular}; Stripe→{Adyen, Braintree, Checkout.com, Lemon Squeezy}; Auth0→{Clerk, WorkOS, Okta, FusionAuth, Supertokens}. Every alternative term in the file must either already exist in the public corpus or be queued for ingestion (lint enforces).

### P2 — Web app: Alternatives block
- [ ] Update Open Graph image generator to include contemporaries when present — done when generated OG image for a Kafka entry shows "Alternatives: RabbitMQ · NATS · Redpanda" subtitle.
- [ ] Update `/stats` page to show "% of public entries w/ ≥ 1 contemporary populated" — done when stat renders and queries DB at request time.
- [ ] Add team-admin UI for editing contemporaries on team entries — done when team admins can add/remove via the entry edit form.
- [ ] Add personal-entry contemporaries input — done when users can set contemporaries on personal entries.

### Acceptance gate additions (must pass before declaring v0.1 — these replace/extend the existing acceptance gates)
- [ ] ≥ 60% of public entries in cloud/devops/observability/storage domains have ≥ 1 contemporary populated — verified by `pnpm --filter @wat/ingest contemporaries:coverage`.
- [ ] Search benchmark expanded from 500 acronyms to 1000 mixed entries (500 acronyms + 300 concepts + 200 systems) — verified by `pnpm bench`.
- [ ] Hit-rate target unchanged (≥ 90% top-1, ≥ 98% top-5) on the expanded benchmark — verified by `pnpm bench`.
- [ ] Alternatives block renders correctly across web, ext, Slack, MCP for ≥ 5 reference entries (Kubernetes, Kafka, Postgres, Terraform, Datadog) — verified by E2E.
- [ ] Contemporaries lint passes in CI (no unresolved names, no asymmetric pairs, no self-references) — verified by CI job.

## Folder/root note
Rename folder freely; keep `idea.md` and `todo.md` at project root.
