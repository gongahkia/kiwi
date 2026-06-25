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
- `users:read.email`

User scopes:

- `identity.basic`
- `identity.email`

Do not request `channels:history` or `groups:history` unless channel-wide ingestion is implemented and reviewed. The current message shortcut uses the selected message payload only.

## Events And Interactivity

- `app_mention`
- `app_uninstalled`
- `tokens_revoked`
- message shortcut callback: `wat_explain_acronyms`

## Review Demo Script

1. Install from `/slack/install`.
2. Run `/wat API`.
3. Run `/wat-alt TLS`.
4. Run `/wat-suggest RTO as Recovery Time Objective -- Maximum acceptable restore time.`
5. As a wat team admin, run `/wat-define SLO as Service Level Objective -- Reliability target for a service.`
6. Use message shortcut "Explain acronyms" on a message containing `TLS` and `API`.
7. Uninstall the app and confirm the `slack_installs` row is removed.

## Data Handling

- No passive channel history ingestion.
- Slash commands send only command text plus Slack user/workspace IDs.
- Message shortcuts send only the selected message payload.
- `/wat-define` resolves the Slack user's email with `users.info` to check wat team-admin status.
- OAuth bot/user tokens are encrypted at rest.
- Install rows are deleted on `app_uninstalled` or `tokens_revoked`.

## Support Links

- Privacy: `/privacy`
- Security: `docs/security-model.md`
- Production readiness: `docs/production-readiness.md`
