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

`rotate-secrets.sh` reuses `generate-secrets.sh` and prints replacement `AUTH_SECRET`, `WAT_API_KEY`, and `SLACK_TOKEN_ENCRYPTION_KEY` values. Update deployment secrets, restart services, verify login/search, then revoke old credentials.
