#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/examples/rendered"

mkdir -p "$OUT"

for source in "$ROOT"/examples/*.mmd; do
  name="$(basename "$source" .mmd)"
  cargo run -q -p kumeyuri-cli -- render "$source" \
    --format svg \
    --theme github \
    --dark-theme tokyo-night \
    --charset unicode \
    --padding 12 \
    > "$OUT/$name.svg"
  cargo run -q -p kumeyuri-cli -- render "$source" \
    --format gif \
    --theme github \
    --charset unicode \
    --padding 12 \
    > "$OUT/$name.gif"
done
