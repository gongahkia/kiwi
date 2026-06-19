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

Optional values depend on enabled surfaces:

```sh
SLACK_CLIENT_ID=
SLACK_CLIENT_SECRET=
SLACK_SIGNING_SECRET=
SLACK_APP_TOKEN=
```

## Docker Compose

The current compose file starts Postgres:

```sh
docker compose up -d postgres
```

Run the web app against it:

```sh
pnpm install
pnpm db:generate
pnpm dev
```

Target full-stack compose should include:

- web app on `:3000`
- Slack app worker/webhook service
- Postgres with persistent volume
- health checks for `/healthz`, `/readyz`, and Postgres readiness
- seed/import step for the dev corpus

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

Target Terraform path:

```sh
cd infra/fly
terraform init
terraform apply
```

Expected module inputs:

- app name
- region
- `DATABASE_URL`
- `NEXT_PUBLIC_SITE_URL`
- Slack secrets when Slack is enabled

Expected outputs:

- web URL
- app name
- database attachment or DSN reference

## Backups

Postgres backups should use `pg_dump` for logical exports and should include any uploaded/generated assets once file storage exists.

Restore drills should create a new database, load the latest backup, run migrations, and verify `/readyz`.
