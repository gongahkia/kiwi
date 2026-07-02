#!/usr/bin/env bash
set -euo pipefail

bin="${1:-./build/ci/contourtty}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/contourtty-shutdown.XXXXXX")"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

if [[ ! -x "$bin" ]]; then
  echo "missing executable: $bin" >&2
  exit 1
fi

timeout_bin="$(command -v timeout || true)"
if [[ -z "$timeout_bin" && -x /opt/homebrew/bin/timeout ]]; then
  timeout_bin="/opt/homebrew/bin/timeout"
fi
if [[ -z "$timeout_bin" ]]; then
  echo "timeout command not found" >&2
  exit 1
fi

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i testsrc=size=160x90:rate=5:duration=10 \
  -pix_fmt yuv420p -y "$tmp/fixture.mp4"

script_style="bsd"
if ! script -q "$tmp/script-style.typescript" /bin/echo ok >/dev/null 2>&1; then
  script_style="util"
fi

run_pty() {
  local typescript="$1"
  shift
  if [[ "$script_style" == "bsd" ]]; then
    script -q "$typescript" "$@" >/dev/null
    return
  fi
  local command=""
  printf -v command "%q " "$@"
  script -q -c "$command" "$typescript" >/dev/null
}

expect_log() {
  local log_file="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$log_file"; then
    echo "missing log pattern '$pattern' in $log_file" >&2
    sed -n '1,160p' "$log_file" >&2
    exit 1
  fi
}

"$bin" --mode structure --width 24 --height 12 --fps 5 \
  --export "$tmp/normal.ansi" --log "$tmp/normal.log" "$tmp/fixture.mp4" >/dev/null
expect_log "$tmp/normal.log" "exported frames="
expect_log "$tmp/normal.log" "render stats frames="

set +e +o pipefail
run_pty "$tmp/quit.typescript" \
  "$timeout_bin" 30 "$bin" --mode structure --width 24 --height 12 --fps 5 \
  --input-keys q --log "$tmp/quit.log" "$tmp/fixture.mp4"
quit_status=$?
set -e -o pipefail
if [[ "$quit_status" -ne 0 ]]; then
  echo "keyboard quit path failed with status $quit_status" >&2
  exit 1
fi
expect_log "$tmp/quit.log" "scripted input keys queued count=1"
expect_log "$tmp/quit.log" "playback quit before eof"

set +e +o pipefail
run_pty "$tmp/seek.typescript" \
  "$timeout_bin" 40 "$bin" --mode structure --width 24 --height 12 --fps 5 \
  --input-keys $'\033[Cq' --log "$tmp/seek.log" "$tmp/fixture.mp4"
seek_status=$?
set -e -o pipefail
if [[ "$seek_status" -ne 0 ]]; then
  echo "seek path failed with status $seek_status" >&2
  exit 1
fi
expect_log "$tmp/seek.log" "scripted input keys queued count=4"
expect_log "$tmp/seek.log" "seek reset render state target_us="
expect_log "$tmp/seek.log" "playback quit before eof"

set +e
run_pty "$tmp/sigint.typescript" \
  "$timeout_bin" -s INT 8 "$bin" --mode structure --width 24 --height 12 --fps 5 \
  --log "$tmp/sigint.log" "$tmp/fixture.mp4"
sigint_status=$?
set -e
if [[ "$sigint_status" -ne 0 && "$sigint_status" -ne 124 && "$sigint_status" -ne 130 ]]; then
  echo "SIGINT path failed with status $sigint_status" >&2
  exit 1
fi
expect_log "$tmp/sigint.log" "playback quit before eof"

echo "shutdown path smoke ok"
