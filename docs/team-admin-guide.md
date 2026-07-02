# Team Admin Guide

Use this flow after the first admin signs in at `/login?next=/team/admin`. The first user for a new email domain creates the team automatically and lands on the team dashboard checklist.

## 15-minute setup

1. Open `/team/admin/import` and upload the JSON or CSV template after replacing sample rows with team acronyms.
2. Open `/team/admin/api-keys`, create a search-scoped key, and configure Slack, Teams, Discord, MCP, or browser extension clients with that key.
3. Open `/team/admin/members`, invite teammates by email, and share the raw invite token through an approved channel.
4. Ask one teammate to sign in with the invite email; accepted invites assign team membership and role.
5. Search from web or a connected client and confirm team-layer results appear.

## Entries

- Create or edit entries from `/team/admin/entries`.
- Mark entries `needs_review` or `stale` from the entries page when ownership or meaning is unclear.
- Removing an entry deprecates it instead of hard-deleting it, so audit history remains intact while normal search hides it.
- Use `/team/admin/export/json` or `/team/admin/export/csv` before large edits.

## Members

- Admins can invite, promote, demote, and remove members from `/team/admin/members`.
- Pending invites expire after 7 days.
- Member role changes and removals write team audit events.

## Review

- Open `/team/admin/review` for suggested edits.
- Approved new-entry suggestions create team entries and audit records.
- Rejected suggestions remain visible in review history.

## Dashboard

`/team/admin` shows team entries, pending suggestions, stale entries, source coverage, top returned glossary terms, no-result hashes, search latency, and recent audit activity.

## API Keys

- Use `search` keys for lookup-only clients.
- Use `suggest` keys for suggestion clients.
- Use `admin` only for trusted import or management automation.
- Revoke unused keys from `/team/admin/api-keys`.
