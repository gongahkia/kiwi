# Production Readiness Checklist

Use this before exposing a hosted or self-hosted wat deployment to real team data.

## Required Secrets

- `DATABASE_URL`
- `AUTH_SECRET`
- `NEXT_PUBLIC_SITE_URL`
- `SLACK_TOKEN_ENCRYPTION_KEY` when Slack tokens are stored
- `SLACK_APP_TOKEN`, `SLACK_BOT_TOKEN`, and `SLACK_SIGNING_SECRET` when Slack Socket Mode is enabled
- `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`, `SLACK_REDIRECT_URI`, and `SLACK_STATE_SECRET` when Slack OAuth install is enabled
- `SLACK_INSTALL_STORE=postgres` and `SLACK_DATABASE_URL`/`DATABASE_URL` for hosted Slack installs
- `SLACK_METRICS_TOKEN` when exposing Slack runtime `/metrics`
- `WAT_SLACK_TEAM_MAP` or a DB-backed team mapping before accepting Slack installs
- Slack OAuth values when distributed installs are enabled
- `TEAMS_PUBLIC_ORIGIN`, `TEAMS_APP_ID`, and `TEAMS_API_SECRET_REGISTRATION_ID` when rendering the Teams app package
- `TEAMS_METRICS_TOKEN` when exposing Teams metrics
- `DISCORD_PUBLIC_KEY` when Discord interactions are enabled
- `DISCORD_APPLICATION_ID` and `DISCORD_BOT_TOKEN` when registering Discord commands
- `DISCORD_INSTALL_SCOPES`, `DISCORD_INSTALL_GUILD_ID`, and `DISCORD_BOT_PERMISSIONS` when exposing `/discord/install`
- `DISCORD_INSTALL_STORE=postgres` and `DISCORD_DATABASE_URL`/`DATABASE_URL` for hosted Discord installs
- `DISCORD_METRICS_TOKEN` when exposing Discord runtime `/metrics`
- `WAT_DISCORD_GUILD_MAP` or DB-backed `discord_installs` rows before accepting Discord team writes
- OAuth provider secrets when Google or Slack login is enabled

Post-deploy, create team API keys from `/team/admin/api-keys` for Slack, Teams, Discord, MCP, browser extension, and trusted automation. Do not configure the web app with a global API key.

If this is a first-run environment with no admin session yet, create the initial admin and one-time API key from the CLI:

```sh
pnpm bootstrap:admin -- --migrate --email admin@example.com --team-name "Example"
```

Generate first-run values with:

```sh
./scripts/generate-secrets.sh
```

Store secrets in the deployment secret manager, not in the repo.

Production web startup validates required env values and fails before serving traffic when required secrets are missing, placeholders, or localhost-only defaults.

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

- Configure the deploy release phase to run `DATABASE_URL="$DATABASE_URL" pnpm db:deploy`.
- `db:deploy` applies pending migrations and imports the checked-in public corpus idempotently.
- Verify `/readyz` after the release phase.
- Verify `GET /api/v1/search?q=API&limit=1`.

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
- App middleware blocks obvious SQLi/XSS/path probes with `request_blocked`; mirror these patterns in the hosting WAF or edge firewall before launch.

## Monitoring

Dashboard should show:

- request rate and error rate
- p50/p95 latency for web and search
- DB connection count, CPU, storage, and slow queries
- search no-result rate
- migration/seed/import failures
- Slack event failures
- Slack OAuth callback failures
- Slack lookup/write API failures
- Slack uninstall cleanup count
- Teams message-extension search failures
- Discord interaction signature failures
- Discord lookup/write API failures
- scraper/corpus refresh failures

Alert on `/readyz` failure, high API error rate, sustained search latency breach, DB saturation, backup failure, Slack event failure spikes, Teams search error spikes, and Discord interaction failure spikes.

Prometheus-compatible starter rules live at `infra/monitoring/prometheus-alerts.yml`. Validate required alert coverage with `pnpm alerts:check` before release.

## Release Verification

Before marking a deploy healthy:

```sh
curl -f "$NEXT_PUBLIC_SITE_URL/healthz"
curl -f "$NEXT_PUBLIC_SITE_URL/readyz"
curl -f "$NEXT_PUBLIC_SITE_URL/api/v1/search?q=API&limit=1"
```

Then verify enabled surfaces: Slack `/wat`, Slack URL verification if HTTP mode is exposed, browser extension connection test, MCP lookup, and admin import/export if enabled.

Credential-backed smoke scripts are available for platform/API checks:

```sh
WAT_API_BASE_URL="$NEXT_PUBLIC_SITE_URL" WAT_API_KEY="$WAT_API_KEY" pnpm smoke:teams
WAT_API_BASE_URL="$NEXT_PUBLIC_SITE_URL" WAT_API_KEY="$WAT_API_KEY" SLACK_PUBLIC_URL="$SLACK_PUBLIC_URL" pnpm smoke:slack
WAT_API_BASE_URL="$NEXT_PUBLIC_SITE_URL" WAT_API_KEY="$WAT_API_KEY" DISCORD_PUBLIC_URL="$DISCORD_PUBLIC_URL" pnpm smoke:discord
```

By default these scripts avoid writes where possible. Set `SMOKE_WRITE=true` to queue test suggestions, and set `DISCORD_SMOKE_INSTALL=true` with `DISCORD_SMOKE_GUILD_ID` to test Discord install mapping.

For Teams, render `apps/teams/dist/wat-teams-app.zip` with `TEAMS_PUBLIC_ORIGIN`, `TEAMS_APP_ID`, and `TEAMS_API_SECRET_REGISTRATION_ID`, upload through Teams Developer Portal or Agents Toolkit, and smoke-test compose-box search.

```sh
curl -f -H "Authorization: Bearer $WAT_API_KEY" "$NEXT_PUBLIC_SITE_URL/api/v1/teams/search?q=API"
curl -f -H "Authorization: Bearer $TEAMS_METRICS_TOKEN" "$NEXT_PUBLIC_SITE_URL/api/v1/teams/metrics"
```

For Slack OAuth, also verify:

```sh
curl -I "$SLACK_PUBLIC_URL/slack/install"
curl -f -H "Authorization: Bearer $SLACK_METRICS_TOKEN" "$SLACK_PUBLIC_URL/metrics"
```

Confirm the callback stores an encrypted install record in `slack_installs`, `app_uninstalled` or `tokens_revoked` removes that row, `/wat-suggest` creates a `suggested_edits` row with `team_id`, and no plaintext `xoxb-` or `xoxp-` token appears in logs or storage.

For Discord, register commands, set the Interactions Endpoint URL, insert a guild mapping, and smoke-test lookup/write flows.

```sh
DISCORD_GUILD_ID="$DISCORD_GUILD_ID" pnpm --filter @wat/discord commands:register
curl -f "$DISCORD_PUBLIC_URL/healthz"
curl -f -H "Authorization: Bearer $DISCORD_METRICS_TOKEN" "$DISCORD_PUBLIC_URL/metrics"
curl -f -X POST "$NEXT_PUBLIC_SITE_URL/api/v1/discord/installations" \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Wat-Team-Id: team_123" \
  --data '{"discord_guild_id":"guild_123","application_id":"discord-app-id"}'
```

Confirm `/wat-suggest` creates a `suggested_edits` row with `team_id`, `/wat-define` requires an allowed Discord admin role/user, and invalid Discord signatures return `401`.

## Platform Rollout Order

1. Slack production install path
2. Teams API-based message-extension search
3. Discord commands for companies that already use Discord internally
4. MCP/editor polish
5. Browser extension pairing and policy install

Do not spend production-readiness effort on the web search UI unless it directly supports API/admin, install review, privacy, or platform-directory requirements.
