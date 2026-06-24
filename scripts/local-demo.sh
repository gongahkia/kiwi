#!/usr/bin/env sh
set -eu

postgres_port="${POSTGRES_PORT:-5432}"
mailpit_smtp_port="${MAILPIT_SMTP_PORT:-1025}"
mailpit_http_port="${MAILPIT_HTTP_PORT:-8025}"
web_port="${WAT_WEB_PORT:-3000}"
database_url="${WAT_LOCAL_DEMO_DATABASE_URL:-postgres://wat:wat@localhost:${postgres_port}/wat}"
email_server="smtp://localhost:${mailpit_smtp_port}"
mailpit_url="http://127.0.0.1:${mailpit_http_port}/api/v1/info"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$1 is required"
  fi
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

wait_for_postgres() {
  tries=0
  until docker compose exec -T postgres pg_isready -U wat -d wat >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -gt 60 ]; then
      fail "postgres did not become ready"
    fi
    sleep 1
  done
}

wait_for_mailpit() {
  tries=0
  until curl -fsS "$mailpit_url" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -gt 60 ]; then
      fail "mailpit did not become ready"
    fi
    sleep 1
  done
}

table_exists() {
  docker compose exec -T postgres psql -U wat -d wat -Atc "select to_regclass('public.$1') is not null" | tr -d '[:space:]'
}

need docker
need curl
if ! docker compose version >/dev/null 2>&1; then
  fail "docker compose is required"
fi
if ! command -v pnpm >/dev/null 2>&1 && command -v corepack >/dev/null 2>&1; then
  corepack enable
fi
need pnpm

if [ "${WAT_LOCAL_DEMO_SKIP_INSTALL:-0}" != "1" ]; then
  pnpm install --frozen-lockfile
fi

POSTGRES_PORT="$postgres_port" \
  MAILPIT_SMTP_PORT="$mailpit_smtp_port" \
  MAILPIT_HTTP_PORT="$mailpit_http_port" \
  docker compose up -d postgres mailpit

wait_for_postgres
wait_for_mailpit

if [ "$(table_exists entries)" != "t" ]; then
  DATABASE_URL="$database_url" pnpm db:migrate
else
  printf 'migrations skipped: entries table already exists\n'
fi

DATABASE_URL="$database_url" pnpm db:seed:dev
seed_count="$(docker compose exec -T postgres psql -U wat -d wat -Atc "select count(*) from entries" | tr -d '[:space:]')"
if [ "${seed_count:-0}" -lt 1 ]; then
  fail "seeded corpus check failed"
fi

printf 'db seeded: %s entries\n' "$seed_count"
printf 'mailpit: http://localhost:%s\n' "$mailpit_http_port"

if [ "${WAT_LOCAL_DEMO_CHECK_ONLY:-0}" = "1" ]; then
  exit 0
fi

printf 'web: http://localhost:%s\n' "$web_port"

DATABASE_URL="$database_url" \
  WAT_DATABASE_URL="$database_url" \
  EMAIL_SERVER="$email_server" \
  EMAIL_FROM="wat@localhost" \
  NEXT_PUBLIC_SITE_URL="http://localhost:${web_port}" \
  NEXTAUTH_URL="http://localhost:${web_port}" \
  AUTH_SECRET="${AUTH_SECRET:-local-demo-auth-secret}" \
  NEXTAUTH_SECRET="${NEXTAUTH_SECRET:-local-demo-auth-secret}" \
  pnpm --filter @wat/web exec next dev -p "$web_port"
