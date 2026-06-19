#!/usr/bin/env bash
set -euo pipefail

bin="${1:-./build/ci/contourtty}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/contourtty-terminal.XXXXXX")"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

if [[ ! -x "$bin" ]]; then
  echo "missing executable: $bin" >&2
  exit 1
fi

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

expect_file() {
  local file="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$file"; then
    echo "missing pattern '$pattern' in $file" >&2
    sed -n '1,160p' "$file" >&2
    exit 1
  fi
}

send_quit_keys() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.5
    printf q
  done
}

send_ctrl_c_keys() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.5
    printf '\003'
  done
}

restore_check='before=$(stty -g); stty rows 24 cols 80; "$0" --log "$1"; rc=$?; after=$(stty -g); echo "before=$before"; echo "after=$after"; [ "$before" = "$after" ] || exit 20; exit "$rc"'

set +e +o pipefail
send_quit_keys | run_pty "$tmp/keyboard.typescript" \
  /bin/sh -c "$restore_check" "$bin" "$tmp/keyboard.log"
keyboard_status=$?
set -e -o pipefail
if [[ "$keyboard_status" -ne 0 ]]; then
  echo "keyboard terminal path failed with status $keyboard_status" >&2
  exit 1
fi
expect_file "$tmp/keyboard.log" "terminal session started"
expect_file "$tmp/keyboard.log" "terminal size 80x24"
expect_file "$tmp/keyboard.log" "quit requested by keyboard"
expect_file "$tmp/keyboard.typescript" "before="
expect_file "$tmp/keyboard.typescript" "after="

set +e +o pipefail
send_ctrl_c_keys | run_pty "$tmp/ctrlc.typescript" \
  /bin/sh -c "$restore_check" "$bin" "$tmp/ctrlc.log"
ctrlc_status=$?
set -e -o pipefail
if [[ "$ctrlc_status" -ne 0 ]]; then
  echo "ctrl-c terminal path failed with status $ctrlc_status" >&2
  exit 1
fi
expect_file "$tmp/ctrlc.log" "terminal session started"
expect_file "$tmp/ctrlc.log" "quit requested by signal"

run_pty "$tmp/exception.typescript" /bin/sh -c \
  'before=$(stty -g); CONTOURTTY_THROW_AFTER_TERMINAL=1 "$0" --log "$1"; rc=$?; after=$(stty -g); echo "before=$before"; echo "after=$after"; [ "$before" = "$after" ] || exit 20; [ "$rc" -eq 1 ]' \
  "$bin" "$tmp/exception.log"
expect_file "$tmp/exception.log" "terminal session started"
expect_file "$tmp/exception.typescript" "fatal: forced terminal exception"

echo "terminal path smoke ok"
