# Limitations

wat is not yet a hosted production beta. The current repo is useful for local demo, self-host exploration, and implementation work, but these areas are still incomplete.

## Hosted Auth

- Email login and NextAuth scaffolding exist, but production hosted auth still needs live provider verification.
- API keys are DB-backed per-team keys; external runtimes must use keys created from the team admin API-key page.
- Slack OAuth install exists; browser extension pairing is not complete.

## Persistence

- Web product paths for team entries, personal entries, settings, audit logs, suggestions, API keys, and API rate limits are DB-backed in production.
- Slack workspace installs and tokens can be persisted in DB through `slack_installs`; Slack runtime rate-limit counters are still local/file-backed in the Slack process.
- MCP calls the web API; suggestions write to the shared DB review queue.

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
- Team identity is derived from the Teams API-secret key; optional `teams_installs` mappings are used when an integration gateway supplies `X-Wat-Teams-Tenant-Id`.
- Entra SSO, automatic Microsoft tenant discovery from native Teams API-secret calls, define/suggest writes, and admin flows need later bot/auth work.

## Discord

- Discord support has a signed HTTP interactions runtime, slash commands, a message command, command registration, DB-backed `discord_installs` guild mapping, suggestions, and admin-gated team-entry writes.
- Discord install UX is still operator-driven through `/api/v1/discord/installations`; there is no hosted in-product OAuth/install wizard yet.
- Real App Directory packaging, review assets, and a live guild smoke test are not complete.

## MCP

- The MCP server is a local stdio server that proxies to the web API.
- `@wat/mcp` is not published to npm yet.
- Hosted remote MCP endpoint and catalog submissions are not complete.

## Corpus Coverage

- The public corpus is still seed-sized and should be treated as demo coverage.
- Scraper utilities exist, but scraper outputs are not yet imported into a production-searchable reviewed corpus.
- Bad-delta rollback and broader benchmark gates are not complete.
