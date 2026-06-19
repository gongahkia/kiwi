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
- [ ] Implement email-domain → auto-team join on signup — done when two users w/ same domain land in same team automatically.
- [ ] Implement team creation on first signup of a new domain — done when team row created and user is admin.
- [ ] Add Sentry or self-host error tracking — done when a thrown error in prod surfaces in dashboard.

## P2 — Web app: search UX
- [ ] Implement instant-search w/ React Server Components + Suspense — done when typing shows results in <200ms perceived.

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
- [ ] E2E tests for browser extension (Playwright + WXT testing helpers) — done when hover + sidebar scenarios pass.
- [ ] Slack app integration tests w/ Bolt's test helpers — done when slash + shortcut + mention scenarios pass.
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

## Folder/root note
Rename folder freely; keep `idea.md` and `todo.md` at project root.
