# ADR 0003: Tenancy

## Status

Accepted

## Context

wat needs low-friction team setup for glossary overlays. The first hosted flow should avoid manual tenant provisioning while keeping self-host installs simple.

## Decision

Use verified email domain as the default team boundary.

- The first verified user for a new domain creates the team and becomes admin.
- Later verified users with the same domain join that team as members by default.
- Admins can manage entries, members, roles, domain tags, and team settings.
- Personal entries remain scoped to one user and override team and public layers only for that user.

## Trust model caveats

- Public email domains such as `gmail.com`, `outlook.com`, and `icloud.com` cannot safely imply one organization.
- Shared contractor domains and agencies may group unrelated customers.
- Domain ownership can change, so admin recovery and domain verification need explicit product flows.
- Email-domain tenancy does not prove employment, authorization, or Slack workspace membership.
- SSO and Slack-workspace tenancy can be added later for organizations that need stronger boundaries.

## Rationale

- Email-domain joins are understandable and cheap to operate.
- The model works for hosted and self-hosted installs.
- It matches the initial goal: team-local jargon with minimal setup.

## Consequences

- The app must maintain a denylist or manual-review path for public email domains.
- Admin tools must support member removal and role changes.
- Audit logs must record team membership and entry changes.
- Security-sensitive teams should use self-hosting or a future stronger tenancy mode.
