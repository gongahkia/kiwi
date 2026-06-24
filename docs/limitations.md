# Limitations

wat is not yet a hosted production beta. The current repo is useful for local demo, self-host exploration, and implementation work, but these areas are still incomplete.

## Hosted Auth

- Email login and NextAuth scaffolding exist, but production hosted auth is not the single source for every surface yet.
- Hosted multi-tenant API keys are not DB-backed per-team keys yet; the global `WAT_API_KEY` remains a self-host/dev path.
- OAuth install flows for Slack and browser extension pairing are not complete.

## Persistence

- Postgres schema and migrations exist, but some web product paths still use in-memory runtime stores for team entries, personal entries, suggestions, settings, audit logs, and related admin state.
- Slack rate-limit counters can be file-backed, but Slack workspace installs and tokens are not persisted in DB yet.
- MCP suggestions are file-backed when enabled and do not share the web review queue yet.

## Browser Extension

- The extension is still a scaffold/developer build.
- Chrome, Firefox, and Edge store listings are not published.
- Login/pairing and multi-team picker flows are not complete; users still configure API URL, email, token, and team ID manually or through enterprise policy.

## Slack

- The Slack package has signed-request HTTP scaffolding, Bolt handlers, tests, auth headers, and durable rate limits.
- Production OAuth install, workspace-to-wat team mapping, DB-backed install storage, uninstall lifecycle, and App Directory submission are not complete.
- Deployed `/wat`, `/wat-define`, and `/wat-suggest` flows are not wired end to end against DB-backed team entries yet.

## MCP

- The MCP server is a local stdio server backed by seed/dev fixtures.
- `@wat/mcp` is not published to npm yet.
- Hosted/API or DB-backed lookup, DB-backed suggestions, hosted configuration, and catalog submissions are not complete.

## Corpus Coverage

- The public corpus is still seed-sized and should be treated as demo coverage.
- Scraper utilities exist, but scraper outputs are not yet imported into a production-searchable reviewed corpus.
- License-change alerts, bad-delta rollback, quality sampling, and benchmark gates are not complete.
