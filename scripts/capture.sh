#!/usr/bin/env bash
# regenerate every preset preview gif via vhs. requires vhs, ttyd, ffmpeg on PATH.
# usage: ./scripts/capture.sh [preset-glob]
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v vhs >/dev/null 2>&1; then
	echo "vhs not on PATH. install via 'brew install vhs' (also needs ttyd and ffmpeg)." >&2
	exit 1
fi

glob="${1:-assets/tapes/*.tape}"
shopt -s nullglob
tapes=(${glob})
if [ "${#tapes[@]}" -eq 0 ]; then
	echo "no tapes matched: ${glob}" >&2
	exit 2
fi

for tape in "${tapes[@]}"; do
	echo "==> $tape"
	vhs "$tape"
done
