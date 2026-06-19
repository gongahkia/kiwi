#!/usr/bin/env bash
set -euo pipefail

bin="${1:-./build/ci/contourtty}"
tmp="${TMPDIR:-/tmp}/contourtty-error-paths"
mkdir -p "$tmp"

expect_error() {
  local label="$1"
  local input="$2"
  local pattern="$3"
  local out="$tmp/$label.out"
  local err="$tmp/$label.err"
  if "$bin" "$input" >"$out" 2>"$err"; then
    echo "expected failure for $label" >&2
    return 1
  fi
  grep -q "$pattern" "$err"
}

rm -f "$tmp/missing.mp4"
: >"$tmp/zero.bin"
printf 'not really media' >"$tmp/corrupt.mp4"
ffmpeg -v error -f lavfi -i sine=frequency=1000:sample_rate=44100 -t 0.2 -c:a aac -y "$tmp/audio-only.m4a"

expect_error missing "$tmp/missing.mp4" 'fatal: missing file:'
expect_error zero "$tmp/zero.bin" 'fatal: empty file:'
expect_error corrupt "$tmp/corrupt.mp4" 'fatal: corrupt or unsupported media:'
expect_error audio_only "$tmp/audio-only.m4a" 'fatal: no video stream found:'

echo "error path smoke ok"
