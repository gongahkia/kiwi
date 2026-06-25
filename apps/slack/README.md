# wat Slack App

Primary chat surface for glossary lookup from conversations.

## Install

The Slack app package is scaffolded in `apps/slack`.

```sh
pnpm install
pnpm --filter @wat/slack build
```

Target local development uses Slack Socket Mode for commands, shortcuts, and mentions. HTTP mode remains available for health checks and Slack URL verification. Slack HTTP endpoints require signed requests and reject missing or replayed signatures.

Required environment:

```sh
SLACK_CLIENT_ID=
SLACK_CLIENT_SECRET=
SLACK_SIGNING_SECRET=
SLACK_APP_TOKEN=
SLACK_BOT_TOKEN=
SLACK_REDIRECT_URI=https://wat.example.com/slack/oauth/callback
SLACK_STATE_SECRET=
SLACK_SOCKET_MODE=true
SLACK_ADMIN_USER_IDS=U123,U456
SLACK_INSTALL_STORE=postgres
SLACK_INSTALL_STORE_PATH=.wat-slack-installs.json
SLACK_METRICS_TOKEN=
SLACK_TOKEN_ENCRYPTION_KEY=
SLACK_DATABASE_URL=postgres://wat:wat@localhost:5432/wat
WAT_API_BASE_URL=http://localhost:3000
WAT_API_KEY=
WAT_SLACK_TEAM_MAP=T123:team_123
WAT_TEAM_ID=
SLACK_RATE_LIMIT_STORE_PATH=.wat-slack-rate-limits.json
SLACK_WORKSPACE_RATE_LIMIT=30
SLACK_CHANNEL_RATE_LIMIT=30
SLACK_USER_RATE_LIMIT=30
SLACK_WORKSPACE_RATE_LIMIT_WINDOW_MS=60000
```

When `WAT_API_KEY` and `WAT_TEAM_ID` are set, wat lookup/write calls include `Authorization: Bearer <key>`, `X-Wat-Team-Id`, and `X-Wat-User-Id: slack:<user id>`. The key must be a DB-backed team API key and `WAT_TEAM_ID` must match that key's team.

`SLACK_BOT_TOKEN` is required when `SLACK_SOCKET_MODE=true`. `SLACK_ADMIN_USER_IDS` is a dev override; production `/wat-define` should rely on Slack user email lookup plus `/api/v1/team/admin-check`.

## OAuth Install

- `GET /slack/install` redirects to Slack `oauth/v2/authorize`.
- `GET /slack/oauth/callback` verifies signed state, exchanges the code with Slack, encrypts bot/user tokens, and stores the install record.
- `SLACK_INSTALL_STORE=postgres` writes to `slack_installs`; `json` uses `SLACK_INSTALL_STORE_PATH`; `memory` is test-only.
- `WAT_SLACK_TEAM_MAP` maps Slack workspace IDs to wat team IDs with comma-separated `T123:team_123` pairs. `WAT_TEAM_ID` is a runtime fallback for single-team self-host installs and must match the API key's team.
- Commands resolve `X-Wat-Team-Id` from the Slack install record first, then `WAT_SLACK_TEAM_MAP`, then `WAT_TEAM_ID`.
- `SLACK_REDIRECT_URI` must match the Slack app OAuth redirect configuration. Slack requires HTTPS for production redirect URLs.
- `app_uninstalled` and `tokens_revoked` events delete the matching install record.

## Monitoring

- `GET /metrics` returns Prometheus-style counters when called with `Authorization: Bearer <SLACK_METRICS_TOKEN>`.
- Runtime logs are JSON and avoid token, secret, authorization, and cookie fields.
- Counters cover OAuth callbacks, uninstall events, Slack Events API requests, commands, lookup/write calls, and admin checks.

## Target Bot Scopes

- `commands`: handle `/wat`, `/wat-define`, and `/wat-suggest`
- `chat:write`: respond with ephemeral or in-thread explanations
- `app_mentions:read`: handle direct bot mentions
- `channels:history`: inspect selected channel messages only for explicit shortcut flows
- `groups:history`: support private-channel shortcut flows after install approval
- `users:read.email`: map installer identity to a wat team by verified email domain

## Target User Scopes

- `identity.basic`: identify the installing user
- `identity.email`: associate the installer with a wat account or team

## Current Runtime

- `/wat <term>` looks up public/team/personal entries through `WAT_API_BASE_URL`.
- `/wat-alt <term>` shows contemporaries/alternatives for the top match.
- `/wat-suggest <term> as <expansion> -- <meaning>` queues a team-scoped DB-backed suggestion for review through `/api/v1/suggestions`.
- `/wat-define <term> as <expansion> -- <meaning>` writes a team entry for configured Slack admins.
- The `wat_explain_acronyms` message shortcut explains acronyms in the selected message payload.
- `app_mention` replies in-thread with a lookup.

## Permissions Model

Slash-command lookup is read-only. Admin definition commands check wat team-admin status by resolving the Slack user email with `users.info` and calling `/api/v1/team/admin-check`. `SLACK_ADMIN_USER_IDS` is a dev override.

Command, shortcut, and mention bursts are rate-limited per workspace, channel, and user. Counters persist to `SLACK_RATE_LIMIT_STORE_PATH` so restarts do not reset active windows.

Message shortcuts should process only the selected message payload Slack sends to the app. Channel-wide auto-detect should be opt-in per channel.

Tokens must be encrypted at rest. Workspace installs should map to wat teams through installer email domain, with manual override for ambiguous or public domains.

## Privacy Notes

The app should not ingest channel history by default. It should send only the explicit command term, selected message text, mention text, or opted-in auto-detect candidate to wat lookup APIs.

wat API calls include the configured API token, configured wat team ID, and `slack:<user id>` for user-level quota scope. The Slack runtime stores rate-limit counters when `SLACK_RATE_LIMIT_STORE_PATH` is set and encrypted install records through the selected `SLACK_INSTALL_STORE`.
