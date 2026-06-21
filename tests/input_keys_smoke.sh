#!/usr/bin/env bash
set -euo pipefail

bin="${1:?contourtty binary required}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg CLI unavailable; skipping input-keys smoke"
  exit 77
fi
if ! command -v script >/dev/null 2>&1; then
  echo "script(1) unavailable; skipping input-keys smoke"
  exit 77
fi

tmp="${TMPDIR:-/tmp}/contourtty-input-keys-$$"
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
  if script -q "$tmp/probe.typescript" /bin/echo ok >/dev/null 2>&1; then
    script -q "$output" "$@" >/dev/null
  else
    local command
    printf -v command '%q ' "$@"
    script -q -c "$command" "$output" >/dev/null
  fi
}

run_pty "$typescript" "$bin" \
  --input-keys ism246q \
  --width 40 \
  --height 12 \
  --fps 1000 \
  --color-mode mono \
  --log "$log" \
  "$input"

grep -q "scripted input keys queued count=7" "$log"
grep -q "osd shown" "$log"
grep -q "live style mode=luminance style=painterly" "$log"
grep -q "live mode mode=structure style=painterly" "$log"
grep -q "live edge .* edge=0.40" "$log"
grep -q "live dog .* dog=0.10" "$log"
grep -q "live contrast .* contrast=0.10" "$log"
