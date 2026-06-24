# wat Slack App

Slack surface for glossary lookup from conversations.

## Install

The Slack app package is scaffolded in `apps/slack`.

```sh
pnpm install
pnpm --filter @wat/slack build
```

Target local development uses Slack socket mode for commands and shortcuts, plus an HTTP endpoint for OAuth install callbacks. Slack HTTP endpoints require signed requests and reject missing or replayed signatures.

Required environment:

```sh
SLACK_CLIENT_ID=
SLACK_CLIENT_SECRET=
SLACK_SIGNING_SECRET=
SLACK_APP_TOKEN=
WAT_API_BASE_URL=http://localhost:3000
WAT_API_KEY=
WAT_TEAM_ID=
SLACK_RATE_LIMIT_STORE_PATH=.wat-slack-rate-limits.json
SLACK_WORKSPACE_RATE_LIMIT=30
SLACK_CHANNEL_RATE_LIMIT=30
SLACK_USER_RATE_LIMIT=30
SLACK_WORKSPACE_RATE_LIMIT_WINDOW_MS=60000
```

When `WAT_API_KEY` and `WAT_TEAM_ID` are set, wat lookup/write calls include `Authorization: Bearer <key>`, `X-Wat-Team-Id`, and `X-Wat-User-Id: slack:<user id>`.

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

## Permissions Model

Slash-command lookup is read-only. Admin definition commands should require Slack workspace admin status plus wat team admin status before writing team entries.

Command, shortcut, and mention bursts are rate-limited per workspace, channel, and user. Counters persist to `SLACK_RATE_LIMIT_STORE_PATH` so restarts do not reset active windows.

Message shortcuts should process only the selected message payload Slack sends to the app. Channel-wide auto-detect should be opt-in per channel.

Tokens must be encrypted at rest. Workspace installs should map to wat teams through installer email domain, with manual override for ambiguous or public domains.

## Privacy Notes

The app should not ingest channel history by default. It should send only the explicit command term, selected message text, mention text, or opted-in auto-detect candidate to wat lookup APIs.

wat API calls include the configured API token, configured wat team ID, and `slack:<user id>` for user-level quota scope. The Slack scaffold stores rate-limit counters when `SLACK_RATE_LIMIT_STORE_PATH` is set; production install records and bot tokens must be encrypted at rest before directory submission.
