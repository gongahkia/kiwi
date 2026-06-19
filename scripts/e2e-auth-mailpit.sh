#!/bin/sh
set -eu

database_url="postgres://wat:wat@127.0.0.1:55433/wat_auth_e2e"

POSTGRES_PORT=55433 docker compose up -d --wait --force-recreate postgres mailpit
POSTGRES_PORT=55433 docker compose exec -T postgres psql -U wat -d postgres -c "drop database if exists wat_auth_e2e with (force);"
POSTGRES_PORT=55433 docker compose exec -T postgres psql -U wat -d postgres -c "create database wat_auth_e2e owner wat;"

DATABASE_URL="$database_url" pnpm db:migrate
MAILPIT_HTTP_URL="${MAILPIT_HTTP_URL:-http://127.0.0.1:8025}" pnpm exec playwright test e2e/auth-email.spec.ts --config playwright.auth.config.ts
