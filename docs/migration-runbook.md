# Migration Runbook

Use this runbook when upgrading a self-hosted wat install or recovering from a bad migration.

## Before Upgrade

1. Read the release notes and check for required env changes.
2. Confirm `DATABASE_URL` points at the intended database.
3. Confirm Postgres has required extensions:

```sql
create extension if not exists pg_trgm;
create extension if not exists vector;
```

4. Capture a backup:

```sh
DATABASE_URL="$DATABASE_URL" BACKUP_DIR=backups ./scripts/backup.sh
```

5. Keep the produced archive path with the deployment record.

## Run Migrations And Public Seed

Run the idempotent release step from the repo root:

```sh
DATABASE_URL="$DATABASE_URL" pnpm db:deploy
```

Then verify the application path:

```sh
curl -f http://localhost:3000/healthz
curl -f http://localhost:3000/readyz
curl -f 'http://localhost:3000/api/v1/search?q=API&limit=1'
```

For Docker Compose, run the migration command against the compose DSN before sending normal traffic to the upgraded web container.

## Back Up

The backup script writes a gzipped archive containing:

- `database.sql` from `pg_dump`
- `uploads.tar` for `UPLOADS_DIR` when present
- `manifest.txt` with backup creation metadata

Required env:

```sh
DATABASE_URL=postgres://...
BACKUP_DIR=backups
UPLOADS_DIR=uploads
```

## Restore

Restore into a new empty database when possible:

```sh
DATABASE_URL="$RESTORE_DATABASE_URL" \
BACKUP_ARCHIVE=backups/wat-backup-YYYYMMDDTHHMMSSZ.tar.gz \
UPLOADS_DIR=uploads \
./scripts/restore.sh
```

After restore:

```sh
DATABASE_URL="$RESTORE_DATABASE_URL" pnpm --filter @wat/db db:migrate
curl -f http://localhost:3000/readyz
curl -f 'http://localhost:3000/api/v1/search?q=API&limit=1'
```

## Roll Back

If a web/API deploy is bad but the database migration is compatible, roll back the web image and keep the current database.

Hosted/Fly.io rollback:

1. Freeze non-critical writes: corpus imports, bulk admin imports, and platform write smoke tests.
2. Identify the last healthy image from the deployment record or Fly release history.
3. Update `infra/fly` with the known-good `web_image` and run `terraform apply`; do not change `DATABASE_URL`.
4. Restart Slack, Discord, MCP, or worker runtimes only if they were deployed from the bad revision.
5. Verify the rolled-back web/API surface:

```sh
pnpm smoke:deployment -- --url "$NEXT_PUBLIC_SITE_URL"
WAT_API_BASE_URL="$NEXT_PUBLIC_SITE_URL" WAT_API_KEY="$WAT_API_KEY" pnpm smoke:platforms
```

6. Confirm no rollback data loss: compare `audit_log`, `suggested_edits`, `team_entries`, `api_keys`, `slack_installs`, `discord_installs`, and `teams_installs` row counts/timestamps before and after rollback when DB access is available.
7. Keep the bad image tag, logs, and deploy ID for root-cause analysis; do not rerun migrations from the bad revision.

If a migration is bad:

1. Stop writes: imports, admin edits, suggestions, Slack write commands, and extension custom-entry saves.
2. Restore the latest known-good backup into a new database.
3. Point `DATABASE_URL` at the restored database.
4. Restart web, Slack, and MCP services.
5. Verify `/healthz`, `/readyz`, and search.
6. Compare audit/import timestamps to identify any writes after the backup.

Do not repoint to an old database that may have divergent writes until data comparison is complete.

## Rotate Secrets During Recovery

When credentials may have leaked or a backup was handled outside trusted infrastructure:

```sh
./scripts/rotate-secrets.sh
```

`rotate-secrets.sh` reuses `generate-secrets.sh` and prints replacement deployment secrets such as `AUTH_SECRET`, `SLACK_TOKEN_ENCRYPTION_KEY`, `SLACK_STATE_SECRET`, and metrics tokens. Update deployment secrets, restart services, verify login/search, then revoke old API keys in `/team/admin/api-keys` and issue replacement keys for external runtimes.
