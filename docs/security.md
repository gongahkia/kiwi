# Security

For tenant, key, Slack permission, extension privacy, and audit-log rules, see [Security Model](security-model.md).

## Threat Model

wat handles public glossary data, team-private entries, personal entries, identities, OAuth tokens, API keys, and audit history.

Primary assets:

- team glossary entries and suggested edits
- personal glossary entries
- user email addresses and team membership
- Slack OAuth tokens and workspace mappings
- MCP/API keys
- source provenance and license metadata
- audit logs

Primary attackers:

- anonymous users probing public endpoints
- authenticated members attempting admin-only actions
- compromised browser extensions or Slack installations
- malicious corpus sources or scraper inputs
- abusive automation attempting enumeration, spam, or injection

## Boundaries

Public corpus reads are anonymous. Team and personal data require authentication and scoped authorization. Admin actions require the admin role for the target team.

Browser extension, Slack, and MCP requests should resolve to the same team/user authorization model as web requests. Surface-specific tokens should not grant broader access than the user or team policy allows.

## Required Controls

- Validate all entry, suggestion, import, and scraper outputs against shared schemas.
- Use parameterized SQL or ORM query builders for database access.
- Escape rendered text by default and avoid raw HTML from corpus sources.
- Enforce role checks on admin endpoints and review actions.
- Store OAuth tokens and API keys encrypted at rest.
- Rate-limit anonymous lookup, authenticated suggestions, Slack commands, and MCP calls.
- Log security-relevant mutations to `audit_log`.
- Keep source URLs and license tags attached to public entries.
- Run dependency, license, SQL injection, and XSS checks in CI.

## Data Handling

Do not log raw private glossary definitions, OAuth tokens, API keys, magic links, or session cookies.

Search analytics should use query hashes and aggregate metrics. Team and user identifiers should be minimized in analytics output.

Exports must be scoped to the requesting user or team and should include provenance so downstream users can audit source and license obligations.

## Corpus Ingestion Risks

Scrapers process untrusted remote content. Scraper output must be treated as data, not executable content.

Corpus PRs should show added, changed, and removed counts plus sample diffs. License changes must be reviewed before import.

Entries without acceptable provenance should be excluded or marked for review instead of published as authoritative definitions.

## Responsible Disclosure

Report vulnerabilities privately before public disclosure. Include:

- affected endpoint, package, or surface
- reproduction steps
- impact and required privileges
- logs or screenshots if safe to share

Use GitHub private vulnerability reporting when available. If it is unavailable, open a minimal public issue asking for a maintainer security contact without posting exploit details.

Maintainers should acknowledge reports within 72 hours, triage severity, publish fixes with a security note when appropriate, and credit reporters who want attribution.
