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
- Require same-origin `Origin` or `Referer` headers for unsafe cookie-authenticated mutations.
- Store OAuth tokens and API keys encrypted at rest.
- Rate-limit anonymous lookup, authenticated suggestions, Slack commands, and MCP calls.
- Rate-limit custom-entry saves and team imports per actor to slow write spam.
- Log security-relevant mutations to `audit_log`.
- Keep source URLs and license tags attached to public entries.
- Run dependency, license, SQL injection, and XSS checks in CI.
- Cover glossary term, expansion, meaning, source, and domain rendering with XSS regression tests for web, browser extension, and Slack surfaces.

## Security Scans

CI runs local dependency and license checks:

```sh
pnpm audit:deps
pnpm audit:licenses
```

Before a hosted release, run the external scans from an authenticated workstation or CI job:

```sh
SNYK_TOKEN="$SNYK_TOKEN" pnpm audit:deps:snyk
FOSSA_API_KEY="$FOSSA_API_KEY" pnpm audit:licenses:fossa
pnpm audit:licenses:scancode
```

Store the ScanCode output at `artifacts/security/scancode.json` and attach the Snyk/FOSSA result URLs to the release notes. Treat high dependency findings, FOSSA policy failures, or unexpected proprietary/copyleft license detections as release blockers until reviewed.

## Data Handling

Do not log raw private glossary definitions, OAuth tokens, API keys, magic links, or session cookies. Web runtime logs must pass structured fields through the safe logging redactor before console, pino, or error-tracking delivery.

Search analytics should use query hashes and aggregate metrics. Team and user identifiers should be minimized in analytics output.

Exports must be scoped to the requesting user or team and should include provenance so downstream users can audit source and license obligations.

## Corpus Ingestion Risks

Scrapers process untrusted remote content. Scraper output must be treated as data, not executable content.

Corpus PRs should show added, changed, and removed counts plus sample diffs. License changes must be reviewed before import.

Entries without acceptable provenance should be excluded or marked for review instead of published as authoritative definitions.

## Responsible Disclosure

Report vulnerabilities privately before public disclosure:

- Email: <angryapplegravy@gmail.com>
- GitHub security policy: <https://github.com/gongahkia/wat/security/policy>

Do not post exploit details in public issues. Include:

- affected endpoint, package, or surface
- reproduction steps
- impact and required privileges
- logs or screenshots if safe to share

Use GitHub private vulnerability reporting when available. If it is unavailable, email the maintainer directly.

Maintainers should acknowledge reports within 72 hours, triage severity, publish fixes with a security note when appropriate, and credit reporters who want attribution.
