#!/usr/bin/env bash
set -euo pipefail

binary="${1:?missing strok binary}"
config_root="$(mktemp -d)"
trap 'rm -rf "$config_root"' EXIT

report="$(XDG_CONFIG_HOME="$config_root" TERM=xterm-256color COLORTERM=truecolor \
  "$binary" --profile live --doctor --caps unicode=16,kitty)"

require_line() {
  local pattern="$1"
  if ! grep -Eq "$pattern" <<<"$report"; then
    echo "doctor report missing: $pattern" >&2
    printf '%s\n' "$report" >&2
    exit 1
  fi
}

require_line '^doctor_schema=1$'
require_line '^config_source=none$'
require_line '^profile=live$'
require_line '^\[effective_options\]$'
require_line '^mode=luminance$'
require_line '^max_fps=30\.000000$'
require_line '^\[terminal\]$'
require_line '^unicode_version=16$'
require_line '^kitty_graphics=true$'
require_line '^\[analysis_backend\]$'
require_line '^active_backend=(cpu|metal|vulkan)$'
require_line '^\[ffmpeg\]$'
require_line '^version=.+$'
require_line '^rtsp_demuxer_available=(true|false)$'
require_line '^\[shader_tools\]$'
require_line '^glslangValidator=.+$'
require_line '^\[camera\]$'
require_line '^ffmpeg_input_device_available=(true|false)$'
