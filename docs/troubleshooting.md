# Troubleshooting

## Missing DB Extensions

Symptoms:

- migrations fail while creating trigram or vector indexes
- `/readyz` fails after deploy
- DB logs mention `pg_trgm`, `vector`, or unknown operator classes

Checks:

```sql
select extname from pg_extension where extname in ('pg_trgm', 'vector');
```

Fix:

```sql
create extension if not exists pg_trgm;
create extension if not exists vector;
```

Then rerun migrations and verify:

```sh
pnpm --filter @wat/db db:migrate
curl -f http://localhost:3000/readyz
curl -f 'http://localhost:3000/api/v1/search?q=API'
```

## Email Login Failures

Symptoms:

- magic link form stays in error state
- Mailpit receives no email
- production SMTP provider rejects messages

Checks:

- `NEXT_PUBLIC_SITE_URL` matches the public web origin.
- `AUTH_SECRET` is set and stable across restarts.
- SMTP host, port, username, password, and from-address env vars match the provider.
- In local Compose, Mailpit is reachable at `http://localhost:8025`.

Fix:

Restart web after env changes, request a new magic link, and inspect web logs for SMTP status. Do not reuse old links after rotating `AUTH_SECRET`.

## Extension Auth Failures

Symptoms:

- extension connection test reports unauthorized
- lookups return `401`
- team entries are missing from extension results

Checks:

- `apiBaseUrl` points at the web origin, not the extension origin.
- `apiToken` matches the server `WAT_API_KEY` for self-host/dev.
- `accountEmail` is set so requests include `X-Wat-User-Id`.
- `teamId` is set when team-scoped lookups or writes are expected.
- `WAT_EXTENSION_ORIGINS` includes the installed extension origin.

Fix:

Update extension options or managed storage policy, reload the extension, then run the connection test again.

## Slack Signature Errors

Symptoms:

- Slack events return `401`
- webhooks log `invalid_slack_signature`
- URL verification fails

Checks:

- `SLACK_SIGNING_SECRET` matches the Slack app credentials page.
- The request body is passed to verification before JSON parsing.
- System clock skew is under Slack's replay window.
- Slack request URL points at the deployed `/slack/events` endpoint.

Fix:

Rotate the signing secret only after updating deployed env, redeploy the Slack service, then retry Slack URL verification.

## Teams Message Extension Errors

Symptoms:

- Teams upload reports manifest or package validation errors
- message extension search returns `401`
- search opens but cards are blank

Checks:

- `pnpm --filter @wat/teams test` passes.
- `apps/teams/dist/wat-teams-app.zip` was rendered with `TEAMS_PUBLIC_ORIGIN`, `TEAMS_APP_ID`, and `TEAMS_API_SECRET_REGISTRATION_ID`.
- Teams Developer Portal API secret matches `WAT_API_KEY`.
- `WAT_TEAM_ID` is set for single-team installs.
- `TEAMS_PUBLIC_ORIGIN/api/v1/teams/search?q=API` returns `{ "results": [...] }`.

Fix:

Regenerate and re-upload the package after config changes:

```sh
TEAMS_PUBLIC_ORIGIN=https://wat.example.com \
TEAMS_APP_ID=<teams-app-guid> \
TEAMS_API_SECRET_REGISTRATION_ID=<secret-registration-guid> \
pnpm --filter @wat/teams package:prod
```

## Discord Interaction Errors

Symptoms:

- Discord endpoint validation fails
- interactions return `401`
- slash commands reply `wat request failed`

Checks:

- `DISCORD_PUBLIC_KEY` matches the Discord application public key.
- The request body is verified before JSON parsing.
- Discord Interactions Endpoint URL points at `/discord/interactions`.
- `/discord/install` redirects to `https://discord.com/oauth2/authorize`.
- `discord_installs` or `WAT_DISCORD_GUILD_MAP` maps the guild before write commands are used.
- `WAT_API_KEY` and `WAT_API_BASE_URL` are configured for suggestion/define writes.

Fix:

Redeploy the Discord runtime after env changes, then register or refresh commands:

```sh
DISCORD_GUILD_ID=<guild-id> pnpm --filter @wat/discord commands:register
```

## No Search Results

Symptoms:

- web search returns an empty state for common terms
- API response is `{ "matches": [] }`
- `/readyz` passes but seeded terms are missing

Checks:

- Query uses `q` or `query`; empty strings return validation errors.
- `min_confidence=T4` is present when searching low-confidence or pending entries.
- Seed corpus exists at `packages/ingest/seeds/manual.json` in local/dev mode.
- DB-backed deployments have run migrations and public seed/import jobs.
- Team/personal entries require matching `Authorization`, `X-Wat-User-Id`, and `X-Wat-Team-Id` headers.

Fix:

Verify the public path first:

```sh
curl -f 'http://localhost:3000/api/v1/search?q=API&limit=1'
```

Then verify scoped search with the same headers used by the failing surface:

```sh
curl \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "X-Wat-User-Id: user_123" \
  -H "X-Wat-Team-Id: team_123" \
  'http://localhost:3000/api/v1/search?q=CAP&limit=5&min_confidence=T4'
```

If public search works but scoped search does not, inspect API key, team ID, and user ID resolution before changing ranking code.
