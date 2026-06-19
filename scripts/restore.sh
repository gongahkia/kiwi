#!/usr/bin/env sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_ARCHIVE:?BACKUP_ARCHIVE is required}"

uploads_dir="${UPLOADS_DIR:-uploads}"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

tar -xzf "$BACKUP_ARCHIVE" -C "$work_dir"

test -s "$work_dir/database.sql"
test -f "$work_dir/uploads.tar"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$work_dir/database.sql"

mkdir -p "$uploads_dir"
tar -C "$uploads_dir" -xf "$work_dir/uploads.tar"

printf 'restored %s\n' "$BACKUP_ARCHIVE"
