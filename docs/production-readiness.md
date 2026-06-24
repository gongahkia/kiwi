# Production Readiness Checklist

Use this before exposing a hosted or self-hosted wat deployment to real team data.

## Required Secrets

- `DATABASE_URL`
- `AUTH_SECRET`
- `NEXT_PUBLIC_SITE_URL`
- `WAT_API_KEY` for self-host/dev API access until DB-backed per-team keys replace it
- `SLACK_TOKEN_ENCRYPTION_KEY` when Slack tokens are stored
- Slack OAuth/signing values when Slack is enabled
- OAuth provider secrets when Google or Slack login is enabled

Generate first-run values with:

```sh
./scripts/generate-secrets.sh
```

Store secrets in the deployment secret manager, not in the repo.

## Database Extensions

Postgres must have:

```sql
create extension if not exists pg_trgm;
create extension if not exists vector;
```

Verify before migrations:

```sql
select extname from pg_extension where extname in ('pg_trgm', 'vector');
```

## Migrations And Seeds

- Run `DATABASE_URL="$DATABASE_URL" pnpm --filter @wat/db db:migrate` during deploy.
- Verify `/readyz` after migrations.
- Verify `GET /api/v1/search?q=API&limit=1`.
- Confirm the public seed/import job has loaded corpus rows before accepting traffic.

## Backups And Restore

- Schedule `scripts/backup.sh` or provider-native Postgres backups daily.
- Store backup archives outside the primary app host.
- Run a restore drill into a new database at least monthly.
- After restore, rerun migrations and verify `/readyz` plus search.

## TLS And Network

- Serve web and API traffic only over HTTPS.
- Terminate TLS at the platform load balancer or ingress.
- Restrict database access to app/runtime networks.
- Configure `NEXT_PUBLIC_SITE_URL`, OAuth callback URLs, Slack request URLs, and extension origins to use the production HTTPS origin.

## Rate Limits

- Configure lookup limits for anonymous, user, and team scopes.
- Configure suggestion/custom-entry write limits.
- Configure Slack workspace/channel/user limits.
- Use Redis/Upstash/Postgres-backed limits for hosted multi-instance deployments; in-memory limits are dev-only.

## Monitoring

Dashboard should show:

- request rate and error rate
- p50/p95 latency for web and search
- DB connection count, CPU, storage, and slow queries
- search no-result rate
- migration/seed/import failures
- Slack event failures
- scraper/corpus refresh failures

Alert on `/readyz` failure, high API error rate, sustained search latency breach, DB saturation, backup failure, and Slack event failure spikes.

## Release Verification

Before marking a deploy healthy:

```sh
curl -f "$NEXT_PUBLIC_SITE_URL/healthz"
curl -f "$NEXT_PUBLIC_SITE_URL/readyz"
curl -f "$NEXT_PUBLIC_SITE_URL/api/v1/search?q=API&limit=1"
```

Then verify enabled surfaces: browser extension connection test, Slack URL verification or `/wat`, MCP lookup, and admin import/export if enabled.
