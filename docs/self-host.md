# Self-Host

This guide covers the intended self-host paths for wat: Docker Compose, Helm, and Fly.io.

## Requirements

- Node.js and pnpm for local builds
- Postgres 16 with `pg_trgm` and `pgvector`
- Docker for Compose
- kubectl and Helm for Kubernetes
- Terraform and Fly.io CLI for Fly deploys

## Environment

Create an environment file from the project template when `.env.example` is available. Required values:

```sh
DATABASE_URL=postgres://wat:wat@localhost:5432/wat
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

Generate fresh auth/token-encryption secrets for new self-host installs:

```sh
./scripts/generate-secrets.sh
```

Copy the generated `AUTH_SECRET`, `SLACK_TOKEN_ENCRYPTION_KEY`, `SLACK_STATE_SECRET`, `SLACK_METRICS_TOKEN`, `TEAMS_METRICS_TOKEN`, and `DISCORD_METRICS_TOKEN` values into your deployment secret store. Keep `AUTH_SECRET` stable across restarts so existing sessions remain valid. Create team API keys from `/team/admin/api-keys` after login, then use those raw keys as `WAT_API_KEY` values for Slack, Teams, Discord, MCP, browser extensions, or trusted automation.

For first-run installs where no admin can log in yet, bootstrap the first team admin and API key directly against Postgres:

```sh
DATABASE_URL=postgres://wat:wat@localhost:5432/wat \
pnpm bootstrap:admin -- --migrate --email admin@example.com --team-name "Example"
```

The command upserts the team, promotes the user to `admin`, and prints a raw `wat_...` API key once. If an active key with the same name already exists, rerun with `--force-key` to issue another raw key.

Optional values depend on enabled surfaces:

```sh
SLACK_CLIENT_ID=
SLACK_CLIENT_SECRET=
SLACK_SIGNING_SECRET=
SLACK_APP_TOKEN=
SLACK_BOT_TOKEN=
SLACK_REDIRECT_URI=https://wat.example.com/slack/oauth/callback
SLACK_INSTALL_STORE=postgres
WAT_SLACK_TEAM_MAP=T123:team_123
TEAMS_PUBLIC_ORIGIN=https://wat.example.com
TEAMS_APP_ID=
TEAMS_API_SECRET_REGISTRATION_ID=
DISCORD_PUBLIC_KEY=
DISCORD_APPLICATION_ID=
DISCORD_BOT_TOKEN=
DISCORD_INSTALL_SCOPES=applications.commands
DISCORD_INSTALL_STORE=postgres
WAT_DISCORD_GUILD_MAP=guild_123:team_123
```

## Docker Compose

For a local demo with Postgres, Mailpit, seed data, and the web app, run:

```sh
pnpm demo:local
```

The compose file starts Postgres, Mailpit, a one-shot migration/seed job, web, Slack, and Discord services:

```sh
docker compose up --build
```

Expected local endpoints:

- web app: <http://localhost:3000>
- Slack webhook health: <http://localhost:3001/healthz>
- Discord interactions health: <http://localhost:3002/healthz>
- Mailpit: <http://localhost:8025>
- Postgres: `localhost:5432`

The stack includes persistent Postgres storage and health checks for `/readyz`, Slack `/healthz`, Discord `/healthz`, and Postgres readiness. On a clean volume, the migration job applies DB migrations and imports the public seed corpus before web starts. `/readyz` fails until Postgres is reachable, required migrations exist, and at least one public corpus entry is seeded.

Local Compose defaults set `WAT_VALIDATE_ENV=false` because the default URLs and Mailpit SMTP endpoint are localhost-only. Before exposing a self-hosted deployment publicly, set production values in `.env` and run with `WAT_VALIDATE_ENV=true`.

Compose backup and restore use the checked-in scripts:

```sh
DATABASE_URL=postgres://wat:wat@localhost:5432/wat BACKUP_DIR=backups ./scripts/backup.sh
DATABASE_URL=postgres://wat:wat@localhost:5432/wat BACKUP_ARCHIVE=backups/wat-backup-YYYYMMDDTHHMMSSZ.tar.gz ./scripts/restore.sh
curl -f 'http://localhost:3000/api/v1/search?q=API&limit=1'
```

## Helm

Target Kubernetes install path:

```sh
helm install wat charts/wat \
  --set web.env.NEXT_PUBLIC_SITE_URL=https://wat.example.com \
  --set postgresql.auth.database=wat
```

Expected chart components:

- `Deployment` for web
- `Deployment` for Slack app when enabled
- `Deployment` for Discord app when enabled
- `StatefulSet` or external secret/config for Postgres
- `Service` and `Ingress` for web
- liveness probe on `/healthz`
- readiness probe on `/readyz`
- secret references for auth, Slack, Discord, and database credentials

## Fly.io

Terraform path:

```sh
cd infra/fly
terraform init
terraform apply
```

The module in `infra/fly` provisions a single-region web machine, Fly app IPs, health checks, and secrets for auth/OAuth/database configuration. It expects a prebuilt web image and an external Postgres DSN.

After apply, smoke-test the Terraform output URL:

```sh
pnpm smoke:deployment -- --terraform-dir infra/fly
```

## Backups

Postgres backups should use `pg_dump` for logical exports and should include any uploaded/generated assets once file storage exists.

Restore drills should create a new database, load the latest backup, run migrations, and verify `/readyz`.

Before exposing a deployment to team data, review [Production Readiness](production-readiness.md). For upgrade, migration, backup, restore, rollback, and secret-rotation steps, see [Migration Runbook](migration-runbook.md).
