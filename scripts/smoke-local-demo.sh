#!/usr/bin/env sh
set -eu

compose_project="${COMPOSE_PROJECT_NAME:-wat_local_demo_smoke}"
postgres_port="${POSTGRES_PORT:-55432}"
mailpit_smtp_port="${MAILPIT_SMTP_PORT:-11025}"
mailpit_http_port="${MAILPIT_HTTP_PORT:-58025}"
web_port="${WAT_WEB_PORT:-3301}"
database_url="postgres://wat:wat@localhost:${postgres_port}/wat"
log_path="${WAT_LOCAL_DEMO_LOG:-/tmp/wat-local-demo-smoke.log}"
demo_pid=""

cleanup() {
  if [ -n "$demo_pid" ]; then
    kill "$demo_pid" >/dev/null 2>&1 || true
    wait "$demo_pid" >/dev/null 2>&1 || true
  fi
  COMPOSE_PROJECT_NAME="$compose_project" docker compose down -v >/dev/null 2>&1 || true
}

fail() {
  cat "$log_path" >&2 || true
  printf '%s\n' "$1" >&2
  exit 1
}

wait_for_http() {
  url="$1"
  tries=0
  until curl -fsS "$url" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -gt 90 ]; then
      fail "timed out waiting for $url"
    fi
    sleep 1
  done
}

trap cleanup EXIT INT TERM

COMPOSE_PROJECT_NAME="$compose_project" \
  POSTGRES_PORT="$postgres_port" \
  MAILPIT_SMTP_PORT="$mailpit_smtp_port" \
  MAILPIT_HTTP_PORT="$mailpit_http_port" \
  WAT_WEB_PORT="$web_port" \
  WAT_LOCAL_DEMO_DATABASE_URL="$database_url" \
  WAT_LOCAL_DEMO_SKIP_INSTALL="${WAT_LOCAL_DEMO_SKIP_INSTALL:-1}" \
  pnpm demo:local >"$log_path" 2>&1 &
demo_pid="$!"

wait_for_http "http://127.0.0.1:${web_port}/readyz"
curl -fsS "http://127.0.0.1:${web_port}/api/v1/search?q=API&limit=1" >/dev/null
curl -fsS "http://127.0.0.1:${mailpit_http_port}/api/v1/info" >/dev/null

seed_count="$(
  COMPOSE_PROJECT_NAME="$compose_project" docker compose exec -T postgres psql -U wat -d wat -Atc "select count(*) from entries" | tr -d '[:space:]'
)"

if [ "${seed_count:-0}" -lt 1 ]; then
  fail "seeded corpus check failed"
fi

printf 'local demo smoke ok: %s seed entries\n' "$seed_count"
