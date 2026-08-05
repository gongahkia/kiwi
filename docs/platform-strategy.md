# Platform Strategy

wat should optimize for surfaces companies already keep open.

## Priority

1. Slack
2. Microsoft Teams
3. MCP/editor tools
4. Browser extension
5. Discord
6. Web search UI

The web app remains necessary for API routes, auth, install, admin, review, privacy, and support pages. It should not drive product scope unless required by a platform review or admin workflow.

## Slack P0

Goal: make lookup and contribution usable inside Slack before adding another chat app.

Current support:

- OAuth install redirect/callback with signed state
- encrypted local or Postgres install storage backed by `slack_installs`
- command-time Slack workspace to wat team resolution from install records
- explicit Slack workspace to wat team mapping via `WAT_SLACK_TEAM_MAP`
- wat team-admin check for `/wat-define` via Slack `users.info` email lookup and `/api/v1/team/admin-check`
- Socket Mode Bolt runtime
- `/wat <term>` lookup
- `/wat-alt <term>` alternatives
- `/wat-suggest <term> as <expansion> -- <meaning>` review queue write
- `/wat-define <term> as <expansion> -- <meaning>` configured-admin write
- message shortcut acronym lookup
- app mention lookup
- uninstall cleanup for `app_uninstalled` and `tokens_revoked`
- protected `/metrics` counters for Slack runtime monitoring
- Slack manifest and Marketplace checklist in `apps/slack`
- workspace/channel/user rate limits

Next blockers:

- submit the real Slack app to Marketplace/App Directory
- replace explicit `WAT_SLACK_TEAM_MAP` with installer/org-driven hosted team mapping
- wire Slack metrics into the production observability stack

Refs:

- https://docs.slack.dev/tools/bolt-js/concepts/socket-mode/
- https://docs.slack.dev/interactivity/implementing-slash-commands/

## Teams P1

Start with a Teams API-based message extension for search. Microsoft documents API-based message extensions as search-command only, so this is a read path first.

Current support:

- Teams app manifest in `apps/teams/appPackage/manifest.json`
- OpenAPI Description for `GET /api/v1/teams/search`
- adaptive-card response template for Teams search results
- env-rendered upload package under `apps/teams/dist`
- package validation for manifest/OpenAPI/template/icon consistency
- team identity derived from a DB-backed API key
- DB-backed `teams_installs` tenant mapping for gateways or later SSO/bot flows
- protected Teams metrics endpoint

Next blockers:

- replace placeholder API secret registration ID during Developer Portal setup
- automatic tenant identity from Entra SSO or bot invoke payloads
- real tenant sideload and compose/command-box smoke test

Defer:

- define/suggest writes
- bot conversation flows
- admin actions

Refs:

- https://learn.microsoft.com/en-us/microsoftteams/platform/messaging-extensions/create-api-message-extension

## Discord P2

Discord is technically cheap and now has a Slack-like runtime shape. It remains lower company-use priority than Slack/Teams.

Current support:

- signed HTTP interactions endpoint with Ed25519 validation
- PING/PONG endpoint validation
- `/wat term:<term>` slash command
- `/wat-alt term:<term>` alternatives
- `/wat-suggest term:<term> expansion:<expansion> meaning:<meaning>` review queue write
- `/wat-define term:<term> expansion:<expansion> meaning:<meaning>` admin-gated team write
- `Explain acronyms` message command
- ephemeral responses by default
- DB-backed `discord_installs` guild to wat team mapping
- explicit fallback mapping through `WAT_DISCORD_GUILD_MAP`
- protected runtime `/metrics`
- guild/global command registration script

Next blockers:

- real Discord application install and guild smoke test
- App Directory copy/assets if this becomes a distribution target
- hosted team mapping UX instead of operator-written install rows

Refs:

- https://docs.discord.com/developers/interactions/receiving-and-responding
- https://docs.discord.com/developers/interactions/application-commands
