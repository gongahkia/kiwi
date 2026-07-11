#!/usr/bin/env bash
set -euo pipefail

bin="${1:?strok binary required}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg CLI unavailable; skipping render-mode live smoke"
  exit 77
fi
if ! command -v script >/dev/null 2>&1; then
  echo "script(1) unavailable; skipping render-mode live smoke"
  exit 77
fi

tmp="${TMPDIR:-/tmp}/strok-render-mode-live-$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

input="$tmp/input.mp4"
auto_log="$tmp/auto.log"
hybrid_log="$tmp/hybrid.log"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i testsrc2=duration=1:size=96x54:rate=6 \
  -frames:v 6 -pix_fmt yuv420p -y "$input"

run_pty() {
  local output="$1"
  shift
  if script -q "$tmp/probe.typescript" /bin/echo ok >/dev/null 2>&1; then
    script -q "$output" "$@" >/dev/null
  else
    local command
    printf -v command '%q ' "$@"
    script -q -c "$command" "$output" >/dev/null
  fi
}

run_pty "$tmp/auto.typescript" "$bin" \
  --render-mode auto \
  --caps no-kitty,no-sixel,no-iterm \
  --input-keys q \
  --width 40 \
  --height 12 \
  --fps 1000 \
  --color-mode mono \
  --log "$auto_log" \
  "$input"

run_pty "$tmp/hybrid.typescript" "$bin" \
  --render-mode hybrid \
  --caps kitty \
  --input-keys q \
  --width 40 \
  --height 12 \
  --fps 1000 \
  --color-mode truecolor \
  --log "$hybrid_log" \
  "$input"

grep -q "scripted input keys queued count=1" "$auto_log"
grep -q "render mode auto degraded to text" "$auto_log"
grep -q "playback quit before eof" "$auto_log"
grep -q "scripted input keys queued count=1" "$hybrid_log"
grep -q "render mode hybrid protocol=kitty" "$hybrid_log"
grep -q "playback quit before eof" "$hybrid_log"
