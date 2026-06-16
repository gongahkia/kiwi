#!/bin/sh
set -eu

BUDGET_BYTES="${KUMEYURI_WASM_BUDGET_BYTES:-500000}"
OUT_DIR="target/wasm-budget/kumeyuri-render-wasm"

if ! command -v wasm-pack >/dev/null 2>&1; then
  echo "wasm-pack is required for the WASM budget check" >&2
  exit 127
fi

rm -rf "$OUT_DIR"
wasm-pack build crates/kumeyuri-render-wasm --target web --release --out-dir "../../$OUT_DIR" >/dev/null

WASM_FILE="$(find "$OUT_DIR" -maxdepth 1 -type f -name '*.wasm' | sort | head -n 1)"
if [ -z "$WASM_FILE" ]; then
  echo "no .wasm output found in $OUT_DIR" >&2
  exit 1
fi

GZIP_BYTES="$(gzip -9 -c "$WASM_FILE" | wc -c | tr -d '[:space:]')"
echo "kumeyuri-render-wasm gzip bytes: $GZIP_BYTES (budget: < $BUDGET_BYTES)"

if [ "$GZIP_BYTES" -ge "$BUDGET_BYTES" ]; then
  echo "WASM budget exceeded: $GZIP_BYTES >= $BUDGET_BYTES bytes" >&2
  exit 1
fi
