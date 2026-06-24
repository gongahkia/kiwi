# Security Model

This page describes the intended hosted security model and the current self-host/dev escape hatches.

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

Hosted keys should be DB-backed, hashed at rest, and scoped to one team. The current global `WAT_API_KEY` is a self-host/dev escape hatch and should not be used as the hosted multi-tenant model.

Expected hosted key scopes:

- `read`: search public plus authorized team overlays.
- `suggestion-write`: queue suggestions for team review.
- `team-entry-write`: create or update team entries through approved integration paths.
- `admin`: perform team administration APIs where the owning user/team policy allows it.

Key usage metadata should store last-used time, surface, actor, and IP hash without storing raw keys.

## Slack Permissions

Slack should request only the scopes needed for installed workflows.

- `commands`: `/wat`, `/wat-define`, and `/wat-suggest`.
- `chat:write`: ephemeral and thread replies.
- `app_mentions:read`: direct bot mention handling.
- `channels:history` and `groups:history`: selected-message shortcut support after install approval.
- `users:read.email`: map installer identity to a wat team.
- `identity.basic` and `identity.email`: identify the installing user.

Slack workspace identity must map to a wat team before team data is returned. `/wat-define` requires both Slack workspace admin status and wat team admin status. Slack install tokens and bot tokens must be encrypted at rest.

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
- Slack install/uninstall and extension token creation

Audit records should include actor ID, team ID, action, target, timestamp, and safe before/after summaries. They must not store raw API keys, OAuth tokens, session cookies, magic links, or private definition bodies beyond what is required to explain the mutation.
