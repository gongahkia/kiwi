#!/usr/bin/env zsh
set -euo pipefail

readonly ROOT=${0:A:h:h}
readonly MODE=${1:-run}
readonly APP_NAME=Kiwi
readonly BUNDLE_ID=io.github.gongahkia.kiwi
readonly APP="$ROOT/dist/$APP_NAME-dev.app"
readonly MACOS="$APP/Contents/MacOS"
readonly LAUNCHER="$MACOS/$APP_NAME"
readonly PID_FILE="$ROOT/.build/kiwi-dev.pid"
readonly LUAJIT_BIN=${LUAJIT:-$(command -v luajit)}

if [[ "$(uname -s)" != Darwin ]]; then
  print -u2 "build_and_run.sh is the macOS app launcher; use make run on $(uname -s)."
  exit 1
fi

stop_previous() {
  [[ -f "$PID_FILE" ]] || return 0
  local pid=$(<"$PID_FILE")
  if [[ "$pid" == <-> ]] && kill -0 "$pid" 2>/dev/null; then
    local command=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if [[ "$command" == *"$ROOT/src/kiwi/app/main.lua"* ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
}

stage_app() {
  make -C "$ROOT" native terminfo
  rm -rf "$APP"
  mkdir -p "$MACOS"
  print '<?xml version="1.0" encoding="UTF-8"?>' > "$APP/Contents/Info.plist"
  print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$APP/Contents/Info.plist"
  print "<plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>$APP_NAME</string><key>CFBundleIdentifier</key><string>$BUNDLE_ID</string><key>CFBundleName</key><string>$APP_NAME</string><key>CFBundlePackageType</key><string>APPL</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>" >> "$APP/Contents/Info.plist"
  cc -std=c17 -Wall -Wextra -Werror \
    "-DKIWI_SOURCE_ROOT=\"$ROOT\"" \
    "-DKIWI_SOURCE_LUAJIT=\"$LUAJIT_BIN\"" \
    "$ROOT/native/macos_launcher.c" -o "$LAUNCHER"
}

stop_previous
stage_app

case "$MODE" in
  run)
    /usr/bin/open -n "$APP"
    ;;
  --debug|debug)
    exec lldb -- "$LAUNCHER"
    ;;
  --logs|logs)
    /usr/bin/open -n "$APP"
    exec /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    /usr/bin/open -n "$APP"
    exec /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    /usr/bin/open -n "$APP"
    for _ in {1..20}; do
      [[ -s "$PID_FILE" ]] && break
      sleep 0.1
    done
    [[ -s "$PID_FILE" ]]
    ;;
  *)
    print -u2 "usage: $0 [run|--debug|--logs|--telemetry|--verify]"
    exit 2
    ;;
esac
