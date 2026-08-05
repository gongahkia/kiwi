# Slack Marketplace Checklist

## Required Configuration

- Direct Install URL: `https://<slack-public-host>/slack/install`
- OAuth redirect URL: `https://<slack-public-host>/slack/oauth/callback`
- Events request URL for HTTP mode validation: `https://<slack-public-host>/slack/events`
- Metrics endpoint: `https://<slack-public-host>/metrics` protected by `SLACK_METRICS_TOKEN`

## Scopes

Bot scopes:

- `commands`
- `chat:write`
- `app_mentions:read`
- `channels:history`
- `groups:history`
- `users:read.email`

User scopes:

- `identity.basic`
- `identity.email`

Request `channels:history` and `groups:history` only for channel-wide auto-detect. Auto-detect is off by default and must be enabled per channel with `/wat-auto on`.

## Events And Interactivity

- `app_mention`
- `app_uninstalled`
- `message.channels`
- `message.groups`
- `tokens_revoked`
- message shortcut callback: `wat_explain_acronyms`

## Review Demo Script

1. Install from `/slack/install`.
2. Run `/wat API`.
3. Run `/wat-alt TLS`.
4. Run `/wat-suggest RTO as Recovery Time Objective -- Maximum acceptable restore time.`
5. As a wat team admin, run `/wat-define SLO as Service Level Objective -- Reliability target for a service.`
6. Use message shortcut "Explain acronyms" on a message containing `TLS` and `API`.
7. Run `/wat-auto on`, send an unknown acronym, and verify the ephemeral suggestion.
8. Run `/wat-auto off`.
9. Uninstall the app and confirm the `slack_installs` row is removed.

## Data Handling

- No passive channel history ingestion unless `/wat-auto on` is set for the channel.
- Slash commands send only command text plus Slack user/workspace IDs.
- Message shortcuts send only the selected message payload.
- Auto-detect sends only acronym-shaped terms from opted-in channels.
- `/wat-define` resolves the Slack user's email with `users.info` to check wat team-admin status.
- OAuth bot/user tokens are encrypted at rest.
- Install rows are deleted on `app_uninstalled` or `tokens_revoked`.

## Support Links

- Privacy: `/privacy`
- Security: `docs/security-model.md`
- Production readiness: `docs/production-readiness.md`
