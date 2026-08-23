#!/usr/bin/env zsh
set -euo pipefail

readonly ROOT=${0:A:h:h}
readonly MODE=${1:-run}
readonly APP_NAME=Kiwi
readonly BUNDLE_ID=io.github.gongahkia.kiwi
readonly APP="$ROOT/dist/$APP_NAME-dev.app"
readonly MACOS="$APP/Contents/MacOS"
readonly RESOURCES="$APP/Contents/Resources"
readonly LAUNCHER="$MACOS/$APP_NAME"
readonly PID_FILE="$ROOT/.build/kiwi-dev.pid"

if [[ "$(uname -s)" != Darwin ]]; then
  print -u2 "build_and_run.sh is the macOS app launcher; use make run on $(uname -s)."
  exit 1
fi

stop_previous() {
  [[ -f "$PID_FILE" ]] || return 0
  local pid=$(<"$PID_FILE")
  if [[ "$pid" == <-> ]] && kill -0 "$pid" 2>/dev/null; then
    local command=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if [[ "$command" == *"$LAUNCHER"* ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
}

stage_app() {
  make -C "$ROOT" native terminfo
  rm -rf "$APP"
  mkdir -p "$MACOS" "$RESOURCES"
  cp "$ROOT/packaging/macos/Info.plist" "$APP/Contents/Info.plist"
  cp "$ROOT/packaging/macos/Kiwi.sdef" "$RESOURCES/Kiwi.sdef"
  cc -std=c17 -Wall -Wextra -Werror \
    -DKIWI_APP_LUA_ROOT_RELATIVE='"src"' \
    -DKIWI_APP_TERMINFO_RELATIVE='".build/terminfo"' \
    -DKIWI_APP_WGPU_LIBRARY_RELATIVE='".deps/wgpu-native-v29.0.1.1/lib/libwgpu_native.dylib"' \
    -DKIWI_APP_SURFACE_LIBRARY_RELATIVE='".build/native/libkiwi_surface.dylib"' \
    -DKIWI_APP_INTEGRATION_RELATIVE='"integrations/v1"' \
    -DKIWI_APP_RELEASE=0 \
    -DKIWI_APP_PID_FILE_RELATIVE='".build/kiwi-dev.pid"' \
    -DKIWI_APP_ROOT_PARENT_COMPONENTS=2 \
    "$ROOT/native/macos_app_host.c" -o "$LAUNCHER"
}

stop_previous
stage_app

case "$MODE" in
  --stage|stage)
    ;;
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
    print -u2 "usage: $0 [run|--stage|--debug|--logs|--telemetry|--verify]"
    exit 2
    ;;
esac
