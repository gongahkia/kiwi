# Security Model

This page describes the hosted and self-host security model.

## Tenants

Tenant boundary is the wat team.

- Public entries are visible to anonymous users.
- Team entries must be scoped by authenticated team identity.
- Personal entries must be scoped by authenticated user identity and override team/public results only for that user.
- Admin actions must require the admin role for the target team.
- Email-domain auto-join is a convenience boundary, not proof of employment or authorization.
- Public email domains must not auto-create shared teams without invite or manual review.

Cross-tenant reads and writes should fail closed. Exports, imports, member changes, settings, suggestions, search overlays, and audit reads must filter by authenticated `team_id`.

## Keys

API keys are DB-backed, hashed at rest, revocable, and scoped to one team. Raw key values are shown once at creation and are not stored.

Key scopes:

- `search`: search public plus authorized team overlays.
- `suggest`: queue suggestions for team review.
- `write`: create or update team entries through approved integration paths.
- `admin`: perform team administration APIs where the owning user/team policy allows it.

Key usage metadata should store last-used time, surface, actor, and IP hash without storing raw keys.

## Slack Permissions

Slack should request only the scopes needed for installed workflows.

- `commands`: `/wat`, `/wat-define`, and `/wat-suggest`.
- `chat:write`: ephemeral and thread replies.
- `app_mentions:read`: direct bot mention handling.
- `channels:history` and `groups:history`: optional selected-message shortcut support after install approval.
- `identity.basic` and `identity.email`: identify the installing user.

Slack workspace identity must map to a wat team before team data is returned. `/wat-define` must require wat team-admin status before writing team entries; the Slack runtime resolves the user's email with `users.info` and checks wat admin scope through `/api/v1/team/admin-check`. `/wat-suggest` must require team scope before writing review rows. Slack install tokens and bot tokens must be encrypted at rest and deleted when Slack sends uninstall or token-revocation lifecycle events.

## Teams Permissions

The Teams API-based message extension is read-only.

- It exposes one search command with one `q` parameter.
- It uses API-secret service auth for `/api/v1/teams/search`.
- It must not request channel history or message content access.
- Teams API-secret auth uses a DB-backed team API key; team identity is derived from the key.
- If an integration gateway supplies `X-Wat-Teams-Tenant-Id`, wat resolves it through `teams_installs`; unknown supplied tenants fail closed.

Do not add Teams define/suggest/admin writes until tenant mapping and user authorization are stronger than a shared API secret.

## Discord Permissions

Discord uses signed HTTP interactions.

- Every interaction request must validate `X-Signature-Ed25519` and `X-Signature-Timestamp` against `DISCORD_PUBLIC_KEY`.
- Responses should be ephemeral by default and set `allowed_mentions.parse=[]`.
- Guild identity must map to a wat team through `discord_installs` or explicit `WAT_DISCORD_GUILD_MAP` before team data is returned.
- `/wat-suggest` must require team scope before writing review rows.
- `/wat-define` must require Discord Administrator permission, `DISCORD_ADMIN_USER_IDS`, `DISCORD_ADMIN_ROLE_IDS`, or install-scoped `admin_role_ids`.

Discord interactions do not include member email, so this surface cannot use Slack's email-based wat admin check. Role/user allowlists must be treated as the Discord authorization boundary for writes.

## Browser Extension Privacy

The extension should send only the data required for the user-enabled action.

- Lookup sends the term, limit, optional bounded context, account email, team ID, and API token header.
- Hover/highlight context is bounded to hostname, document title, and headings.
- Custom-entry save sends term, expansion, meaning, scope, domains, source URL, and source title after user confirmation.
- Extension storage may contain API base URL, account email, token, team ID, domain filters, feature toggles, and bounded recent lookup cache.

Fresh installs must not send page content automatically. Enterprise policy can preconfigure base URL, team ID, domains, and feature toggles but should not broaden data sent by default.

## Audit Logs

Security-relevant mutations should append audit records inside the same transaction as the data change.

Audit events should include:

- team entry create/update/delete/import
- suggestion create/review/approval/rejection
- member invite/accept/remove and role changes
- team settings changes
- API key create/revoke/rotate
- Slack install/uninstall, Discord install/uninstall, and extension token creation

Audit records should include actor ID, team ID, action, target, timestamp, and safe before/after summaries. They must not store raw API keys, OAuth tokens, session cookies, magic links, or private definition bodies beyond what is required to explain the mutation.
