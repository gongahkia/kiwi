#!/usr/bin/env bash
set -euo pipefail

python="${1:?python executable required}"
runner="${2:?PTY runner required}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/strok-pty-runner.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

transcript="$tmp/transcript"
"$python" "$runner" --transcript "$transcript" --rows 24 --cols 80 -- /bin/sh -c 'stty size; printf "pty runner ok\\n"'

grep -q '24 80' "$transcript"
grep -q 'pty runner ok' "$transcript"
