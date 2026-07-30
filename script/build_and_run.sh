#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOVE_BIN="$(command -v love)"

while [[ -L "$LOVE_BIN" ]]; do
  LOVE_DIR="$(cd -P "$(dirname "$LOVE_BIN")" && pwd)"
  LOVE_BIN="$(readlink "$LOVE_BIN")"
  [[ "$LOVE_BIN" = /* ]] || LOVE_BIN="$LOVE_DIR/$LOVE_BIN"
done

if [[ ! -x "$LOVE_BIN" ]]; then
  echo "love executable unavailable: $LOVE_BIN" >&2
  exit 127
fi

make -C "$ROOT_DIR" check

case "$MODE" in
  run)
    exec "$LOVE_BIN" "$ROOT_DIR"
    ;;
  --debug|debug)
    exec lldb -- "$LOVE_BIN" "$ROOT_DIR"
    ;;
  --verify|verify)
    true
    ;;
    ;;
  *)
    echo "usage: $0 [run|--debug|--verify]" >&2
    exit 2
    ;;
esac
