#!/usr/bin/env bash
set -euo pipefail

bin="${1:?strok binary required}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg CLI unavailable; skipping input-keys smoke"
  exit 77
fi
if ! command -v script >/dev/null 2>&1; then
  echo "script(1) unavailable; skipping input-keys smoke"
  exit 77
fi

tmp="${TMPDIR:-/tmp}/strok-input-keys-$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

input="$tmp/input.mp4"
log="$tmp/play.log"
typescript="$tmp/play.typescript"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i testsrc2=duration=2:size=160x90:rate=12 \
  -frames:v 24 -pix_fmt yuv420p -y "$input"

run_pty() {
  local output="$1"
  shift
  local command
  printf -v command '%q ' "$@"
  if script -q -c '/bin/true' "$tmp/probe.typescript" >/dev/null 2>&1; then
    script -q -c "stty rows 24 cols 80 || exit 1; exec $command" "$output" >/dev/null
  else
    script -q "$output" /bin/sh -c 'stty rows 24 cols 80 || exit 1; exec "$@"' sh "$@" >/dev/null
  fi
}

run_pty "$typescript" "$bin" \
  --input-keys ism246q \
  --width 40 \
  --height 12 \
  --fps 12 \
  --loop \
  --color-mode mono \
  --log "$log" \
  "$input"

expect_log() {
  local pattern="$1"
  if ! grep -q "$pattern" "$log"; then
    echo "missing log pattern '$pattern'" >&2
    sed -n '1,200p' "$log" >&2
    exit 1
  fi
}

expect_log "scripted input keys queued count=7"
expect_log "osd shown"
expect_log "live style mode=luminance style=painterly"
expect_log "live mode mode=structure style=painterly"
expect_log "live edge .* edge=0.40"
expect_log "live dog .* dog=0.10"
expect_log "live contrast .* contrast=0.10"
