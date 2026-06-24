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

Generate fresh auth/API/token-encryption secrets for new self-host installs:

```sh
./scripts/generate-secrets.sh
```

Copy the generated `AUTH_SECRET`, `WAT_API_KEY`, and `SLACK_TOKEN_ENCRYPTION_KEY` values into your deployment secret store. Keep `AUTH_SECRET` stable across restarts so existing sessions remain valid.

Optional values depend on enabled surfaces:

```sh
SLACK_CLIENT_ID=
SLACK_CLIENT_SECRET=
SLACK_SIGNING_SECRET=
SLACK_APP_TOKEN=
```

## Docker Compose

For a local demo with Postgres, Mailpit, seed data, and the web app, run:

```sh
pnpm demo:local
```

The compose file starts Postgres, Mailpit, web, and Slack services:

```sh
docker compose up --build
```

Expected local endpoints:

- web app: <http://localhost:3000>
- Slack webhook health: <http://localhost:3001/healthz>
- Mailpit: <http://localhost:8025>
- Postgres: `localhost:5432`

The stack includes persistent Postgres storage and health checks for `/readyz`, Slack `/healthz`, and Postgres readiness. Run migrations/seeding against the compose DSN before production use.

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
- `StatefulSet` or external secret/config for Postgres
- `Service` and `Ingress` for web
- liveness probe on `/healthz`
- readiness probe on `/readyz`
- secret references for auth, Slack, and database credentials

## Fly.io

Terraform path:

```sh
cd infra/fly
terraform init
terraform apply
```

The module in `infra/fly` provisions a single-region web machine, Fly app IPs, health checks, and secrets for auth/OAuth/database configuration. It expects a prebuilt web image and an external Postgres DSN.

## Backups

Postgres backups should use `pg_dump` for logical exports and should include any uploaded/generated assets once file storage exists.

Restore drills should create a new database, load the latest backup, run migrations, and verify `/readyz`.

Before exposing a deployment to team data, review [Production Readiness](production-readiness.md). For upgrade, migration, backup, restore, rollback, and secret-rotation steps, see [Migration Runbook](migration-runbook.md).
