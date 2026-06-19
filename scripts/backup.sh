#!/usr/bin/env sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"

backup_dir="${BACKUP_DIR:-backups}"
uploads_dir="${UPLOADS_DIR:-uploads}"
timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
work_dir="$(mktemp -d)"
archive="${backup_dir}/wat-backup-${timestamp}.tar.gz"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$backup_dir"

pg_dump "$DATABASE_URL" --format=plain --no-owner --no-privileges >"$work_dir/database.sql"

if [ -d "$uploads_dir" ]; then
  mkdir -p "$work_dir/uploads"
  tar -C "$uploads_dir" -cf "$work_dir/uploads.tar" .
else
  tar -cf "$work_dir/uploads.tar" --files-from /dev/null
fi

cat >"$work_dir/manifest.txt" <<EOF
created_at=${timestamp}
database_dump=database.sql
uploads_archive=uploads.tar
EOF

tar -C "$work_dir" -czf "$archive" database.sql uploads.tar manifest.txt
printf '%s\n' "$archive"
