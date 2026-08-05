# TODO triage — 2026-06-20

`TODO.md` still contains external/manual gates that should not be removed until their stated done conditions are verified.

## Code/config progress in this repo

- CI workflow exists and now runs lint, typecheck, all workspace tests, web E2E, browser-extension E2E, security audits, and full workspace builds.
- DB and Postgres search integration suites run in CI and skip cleanly on local machines without Docker.
- Web auth supports email, optional Google OAuth, and optional Slack OAuth when credentials are configured.
- Web error reporting posts server error payloads to `ERROR_TRACKING_WEBHOOK_URL` and includes a protected smoke-test route.
- Search quality benchmark is runnable with `pnpm bench`; warm HTTP latency and k6 load scripts exist.
- Browser extension has unit/E2E coverage plus Chrome/Firefox store build scripts and a release checklist.
- Slack Bolt handlers cover `/wat`, message shortcut, app mentions, `/wat-define`, and `/wat-suggest` at the handler level.
- MCP server has stdio tests, contract script, and publishable package metadata.
- Fly.io Terraform scaffolding exists for single-region web deploy.
- Dependency audit now passes at `--audit-level high`; production license inventory is scriptable with `pnpm audit:licenses`.

## Still blocked on accounts/manual verification

- npm scope/package reservation and actual package publishing.
- Domain availability/purchase and DNS/TLS setup.
- GitHub org creation and 7-day CI history verification.
- Hosted Neon/Supabase/Vercel/Railway/Fly provisioning and production latency measurements.
- Google/Slack OAuth provider smoke tests with real credentials.
- Browser store, Slack App Directory, MCP registry/catalog submissions.
- Manual cross-browser extension parity checks.
- Launch date, social handles, community posts, beta tester feedback, and launch metric tracking.

## Suggested next verification order

1. Push current commits and confirm CI is green on GitHub.
2. Run `pnpm bench`, `pnpm test:e2e:web`, and `pnpm test:e2e:extension` in CI artifacts.
3. Stand up a hosted web URL and run `pnpm latency:search` plus `pnpm load:search` against it.
4. Configure real OAuth credentials and smoke-test Google/Slack login sessions.
5. Use the release checklists for extension, Slack, MCP, and hosted ops before editing `TODO.md`.
