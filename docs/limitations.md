# Limitations

wat is not yet a hosted production beta. The current repo is useful for local demo, self-host exploration, and implementation work, but these areas are still incomplete.

## Hosted Auth

- Email login and NextAuth scaffolding exist, but production hosted auth is not the single source for every surface yet.
- Hosted multi-tenant API keys are not DB-backed per-team keys yet; the global `WAT_API_KEY` remains a self-host/dev path.
- Slack OAuth install exists; browser extension pairing is not complete.

## Persistence

- Postgres schema and migrations exist, but some web product paths still use in-memory runtime stores for team entries, personal entries, settings, audit logs, and related admin state.
- Slack rate-limit counters can be file-backed; Slack workspace installs and tokens can be persisted in DB through `slack_installs`.
- MCP suggestions are file-backed when enabled and do not share the web review queue yet.

## Browser Extension

- The extension is still a scaffold/developer build.
- Chrome, Firefox, and Edge store listings are not published.
- Login/pairing and multi-team picker flows are not complete; users still configure API URL, email, token, and team ID manually or through enterprise policy.

## Slack

- The Slack package has a Socket Mode Bolt runtime, OAuth install callback, signed-request HTTP scaffolding, handlers, tests, auth headers, and durable rate limits.
- OAuth install records are encrypted and can be stored in JSON locally or Postgres through `slack_installs`.
- App Directory submission is not complete; repo-side manifest, checklist, install URLs, lifecycle handling, and metrics are present.
- `/wat-define` uses wat team-admin checks before writing through `/api/v1/custom-entries`; `SLACK_ADMIN_USER_IDS` remains a dev override.
- `/wat-suggest` writes team-scoped suggestions through `/api/v1/suggestions` into `suggested_edits.team_id`.

## Teams

- Teams support has an API-based message extension package for search only.
- Tenant/team mapping supports the single-team `WAT_TEAM_ID` fallback and DB-backed `teams_installs` mappings when an integration gateway supplies `X-Wat-Teams-Tenant-Id`.
- Entra SSO, automatic Microsoft tenant discovery from native Teams API-secret calls, define/suggest writes, and admin flows need later bot/auth work.

## Discord

- Discord support has a signed HTTP interactions runtime, slash commands, a message command, command registration, DB-backed `discord_installs` guild mapping, suggestions, and admin-gated team-entry writes.
- Discord install UX is still operator-driven through `/api/v1/discord/installations`; there is no hosted in-product OAuth/install wizard yet.
- Real App Directory packaging, review assets, and a live guild smoke test are not complete.

## MCP

- The MCP server is a local stdio server backed by seed/dev fixtures.
- `@wat/mcp` is not published to npm yet.
- Hosted/API or DB-backed lookup, DB-backed suggestions, and catalog submissions are not complete; hosted configuration examples are documented as the target shape.

## Corpus Coverage

- The public corpus is still seed-sized and should be treated as demo coverage.
- Scraper utilities exist, but scraper outputs are not yet imported into a production-searchable reviewed corpus.
- Bad-delta rollback and broader benchmark gates are not complete.
