# On-Call Runbook

## Triage

1. Check hosted status, request error rate, search latency, and deploy history.
2. Identify affected surface: web, API, browser extension, Slack, MCP, or corpus ingestion.
3. Decide severity from user impact, data exposure risk, and rollback availability.
4. Record timeline, owner, mitigation, and follow-up in the incident log.

Prometheus alert rules are checked in at `infra/monitoring/prometheus-alerts.yml`. Grafana starter dashboard JSON is checked in at `infra/monitoring/grafana-dashboard.json`. Run `pnpm alerts:check` and `pnpm dashboard:check` after edits, then import both into the production monitoring workspace before enabling paging.

## DB Failover

Signals:

- `/readyz` fails
- API returns repeated `500`
- database CPU, connection count, or storage alerts fire
- search latency rises with database wait time

Actions:

1. Stop non-critical write paths such as corpus imports and bulk backfills.
2. Check provider database status and latest backup/replica state.
3. Promote the healthy replica or restore the latest backup into a new primary.
4. Rotate `DATABASE_URL` to the new primary.
5. Restart web, Slack, and MCP services.
6. Run migrations in check mode, then verify `/healthz`, `/readyz`, and `GET /api/v1/search?q=API`.
7. Compare recent `audit_log` and corpus import timestamps to identify any missing writes.

Rollback:

- Repoint services to the prior primary only if it is healthy and has no divergent writes.
- Keep failed primary read-only until data comparison is complete.

## Scraper Failure

Signals:

- scheduled corpus refresh fails
- delta PR is missing, malformed, or unexpectedly large
- license scan flags a source change
- benchmark hit-rate drops beyond the allowed threshold

Actions:

1. Disable the failing source job while keeping other sources active.
2. Inspect scraper logs and source response samples.
3. Check for source layout changes, rate limits, license changes, and parser exceptions.
4. Re-run the scraper against a small fixture.
5. Regenerate the delta and compare added, changed, and removed counts.
6. Keep the PR blocked until license and benchmark checks pass.

Rollback:

- Restore the bad delta from a known-good git ref with `pnpm rollback:delta <known-good-ref> data/deltas/<date>/<source>.json`.
- Follow [Corpus Delta Rollback](corpus-rollback.md) for summary regeneration, lint, benchmark, and DB re-import commands.

## Abuse Mitigation

Signals:

- request spikes from one IP, token, team, or workspace
- high no-match rate from automation
- repeated suggestion spam
- SQLi/XSS fuzzing signatures
- Slack command bursts above workspace limits

Actions:

1. Identify the actor key: IP, user ID, team ID, API key, or Slack workspace ID.
2. Apply the narrowest working rate limit or block.
3. Disable write endpoints for the actor if suggestions or imports are abusive.
4. Preserve logs needed for investigation without storing secrets or raw private data.
5. Review whether WAF rules, API limits, or form validation need updates.

Rollback:

- Remove temporary blocks after the attack stops and normal traffic is verified.
- Keep permanent blocks documented with reason, actor key, and expiry.

## Post-Incident

Within two business days:

- publish an internal incident summary
- list user impact and duration
- document root cause and detection gap
- assign prevention follow-ups
- update this runbook if a step was missing or wrong
