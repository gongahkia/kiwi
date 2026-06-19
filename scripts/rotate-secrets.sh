#!/usr/bin/env sh
set -eu

bytes="${SECRET_BYTES:-32}"

generate_secret() {
  openssl rand -base64 "$bytes" | tr -d '\n'
}

cat <<EOF
AUTH_SECRET=$(generate_secret)
WAT_API_KEY=$(generate_secret)
SLACK_TOKEN_ENCRYPTION_KEY=$(generate_secret)
EOF
