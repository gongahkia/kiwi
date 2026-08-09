#!/usr/bin/env bash
set -euo pipefail

bin="${1:-./build/ci/strok}"
requested_mode="${2:-all}"
duration="${STROK_LIVE_ACCEPTANCE_DURATION:-4}"
output_dir="${STROK_LIVE_ACCEPTANCE_OUTPUT:-}"
rtsp_url="${STROK_RTSP_URL:-}"
camera_input="${STROK_CAMERA_INPUT:-}"
transports="${STROK_LIVE_ACCEPTANCE_TRANSPORTS:-tcp,udp}"
image="${STROK_MEDIAMTX_IMAGE:-bluenviron/mediamtx:1}"
port="${STROK_LIVE_ACCEPTANCE_RTSP_PORT:-8554}"
source_cadence="${STROK_LIVE_ACCEPTANCE_SOURCE_CADENCE:-unknown}"
server_name=""
publisher_pid=""
rtsp_fixture_url=""
fixture_codec=""

usage() {
  echo "usage: $0 [strok binary] [all|rtsp|camera]" >&2
}

skip() {
  echo "$*" >&2
  if [[ "${STROK_LIVE_ACCEPTANCE_ALLOW_SKIP:-0}" == "1" ]]; then
    exit 0
  fi
  exit 77
}

if [[ ! -x "$bin" ]]; then
  echo "missing executable: $bin" >&2
  exit 1
fi
if [[ "$requested_mode" != "all" && "$requested_mode" != "rtsp" && "$requested_mode" != "camera" ]]; then
  usage
  exit 1
fi
if [[ ! "$duration" =~ ^[1-9][0-9]*$ ]]; then
  echo "STROK_LIVE_ACCEPTANCE_DURATION must be a positive integer number of seconds" >&2
  exit 1
fi
if [[ ! "$port" =~ ^[1-9][0-9]{0,4}$ ]] || (( port > 65535 )); then
  echo "STROK_LIVE_ACCEPTANCE_RTSP_PORT must be a TCP port" >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  skip "ffmpeg and ffprobe are required; skipping live-input acceptance"
fi
if ! command -v script >/dev/null 2>&1; then
  skip "script(1) is required to capture terminal playback; skipping live-input acceptance"
fi

timeout_bin="$(command -v timeout || true)"
if [[ -z "$timeout_bin" && -x /opt/homebrew/bin/timeout ]]; then
  timeout_bin="/opt/homebrew/bin/timeout"
fi
if [[ -z "$timeout_bin" ]]; then
  skip "timeout command is required; skipping live-input acceptance"
fi

if [[ -z "$output_dir" ]]; then
  output_dir="$(mktemp -d "${TMPDIR:-/tmp}/strok-live-acceptance.XXXXXX")"
else
  mkdir -p "$output_dir"
fi

cleanup() {
  if [[ -n "$publisher_pid" ]]; then
    kill "$publisher_pid" >/dev/null 2>&1 || true
    wait "$publisher_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$server_name" ]]; then
    docker rm -f "$server_name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

script_style="bsd"
if script -q -c '/bin/true' "$output_dir/script-style.typescript" >/dev/null 2>&1; then
  script_style="util"
fi

run_pty() {
  local transcript="$1"
  shift
  if [[ "$script_style" == "util" ]]; then
    local command
    printf -v command '%q ' "$@"
    script -q -c "stty rows 24 cols 80 || exit 1; exec $command" "$transcript" >/dev/null
    return
  fi
  script -q "$transcript" /bin/sh -c 'stty rows 24 cols 80 || exit 1; exec "$@"' sh "$@" >/dev/null
}

redact_input() {
  sed -E 's#(rtsp[s]?://)[^/@]+@#\1***@#'
}

write_metadata() {
  local label="$1"
  local input="$2"
  local transport="$3"
  local max_fps="$4"
  local write_delay="$5"
  {
    printf 'trace=%s\n' "$label"
    printf 'input=%s\n' "$(printf '%s' "$input" | redact_input)"
    printf 'transport=%s\n' "$transport"
    printf 'requested_fps=30\n'
    printf 'max_fps=%s\n' "$max_fps"
    printf 'test_write_delay_ms=%s\n' "$write_delay"
    printf 'duration_seconds=%s\n' "$duration"
    printf 'declared_source_cadence=%s\n' "$source_cadence"
    if [[ -n "$fixture_codec" ]]; then
      printf 'fixture_video_codec=%s\n' "$fixture_codec"
    fi
    printf 'kernel=%s\n' "$(uname -srmo)"
    printf 'strok_version=%s\n' "$("$bin" --version)"
    printf 'ffmpeg_version=%s\n' "$(ffmpeg -version 2>/dev/null | head -n 1)"
  } >"$output_dir/$label.env"
}

require_log() {
  local log="$1"
  local pattern="$2"
  if ! grep -Eq "$pattern" "$log"; then
    echo "missing '$pattern' in $log" >&2
    sed -n '1,220p' "$log" >&2
    exit 1
  fi
}

run_trace() {
  local label="$1"
  local input="$2"
  local transport="$3"
  local max_fps="$4"
  local write_delay="$5"
  local log="$output_dir/$label.log"
  local transcript="$output_dir/$label.typescript"
  local metrics="$output_dir/$label.metrics"
  local metrics_jsonl="$output_dir/$label.metrics.jsonl"
  write_metadata "$label" "$input" "$transport" "$max_fps" "$write_delay"

  set +e
  run_pty "$transcript" env "STROK_TEST_WRITE_DELAY_MS=$write_delay" \
    "$timeout_bin" -s INT -k 2 "$duration" \
    "$bin" --input "$input" --rtsp-transport "$transport" \
      --input-open-timeout 3000 --read-timeout 3000 --reconnect --reconnect-backoff 100 \
      --width 80 --height 22 --no-fit --fps 30 --max-fps "$max_fps" \
      --mode luminance --color-mode mono --debug-stats --log "$log" --metrics-jsonl "$metrics_jsonl"
  local status=$?
  set -e
  if [[ "$status" -ne 0 && "$status" -ne 124 && "$status" -ne 130 ]]; then
    echo "live trace $label exited with status $status" >&2
    sed -n '1,220p' "$log" >&2 || true
    exit 1
  fi

  grep '^\[info\] debug .*live_' "$log" | sed 's/^\[info\] //' >"$metrics"
  require_log "$log" 'live source state=streaming'
  if [[ ! -s "$metrics" ]]; then
    echo "no live metrics were captured for $label" >&2
    sed -n '1,220p' "$log" >&2
    exit 1
  fi
  if [[ ! -s "$metrics_jsonl" ]]; then
    echo "no JSONL metrics were captured for $label" >&2
    sed -n '1,220p' "$log" >&2
    exit 1
  fi
  require_log "$metrics_jsonl" '"schema_version":1'
  require_log "$metrics_jsonl" '"live_decode_to_present_ms_p50":[0-9]'
  if [[ "$write_delay" -gt 0 ]]; then
    require_log "$metrics_jsonl" '"live_(producer_replaced|consumer_discarded)":[1-9]'
    require_log "$metrics_jsonl" '"live_write_overruns":[1-9]'
  else
    require_log "$metrics_jsonl" "\"live_effective_fps\":${max_fps}\\.0+"
  fi
}

start_local_rtsp_fixture() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "the disposable MediaMTX fixture requires Linux host networking; set STROK_RTSP_URL for an external source"
  fi
  if ! command -v docker >/dev/null 2>&1; then
    skip "docker is required for the disposable MediaMTX fixture; set STROK_RTSP_URL for an external source"
  fi
  server_name="strok-live-acceptance-$$"
  docker run --rm -d --network host --name "$server_name" \
    -e "MTX_RTSPADDRESS=127.0.0.1:$port" "$image" >"$output_dir/mediamtx.container"
  sleep 1
  local local_url="rtsp://127.0.0.1:$port/strok-live"
  source_cadence="30fps"
  local -a codec_args
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep 'libx264' >/dev/null; then
    fixture_codec="h264"
    codec_args=(-c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p)
  else
    fixture_codec="mpeg4"
    codec_args=(-c:v mpeg4 -q:v 5)
  fi
  ffmpeg -hide_banner -loglevel warning -re -f lavfi -i testsrc2=size=320x180:rate=30 \
    -an "${codec_args[@]}" -rtsp_transport tcp -f rtsp "$local_url" >"$output_dir/rtsp-publisher.log" 2>&1 &
  publisher_pid=$!
  for _ in {1..30}; do
    if ffprobe -v error -rtsp_transport tcp -select_streams v:0 \
      -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "$local_url" >/dev/null 2>&1; then
      rtsp_fixture_url="$local_url"
      return
    fi
    if ! kill -0 "$publisher_pid" >/dev/null 2>&1; then
      echo "FFmpeg publisher exited before the RTSP fixture became ready" >&2
      sed -n '1,160p' "$output_dir/rtsp-publisher.log" >&2
      exit 1
    fi
    sleep 1
  done
  echo "local MediaMTX RTSP fixture did not become ready" >&2
  sed -n '1,160p' "$output_dir/rtsp-publisher.log" >&2
  exit 1
}

run_rtsp() {
  local input="$rtsp_url"
  if [[ -z "$input" ]]; then
    start_local_rtsp_fixture
    input="$rtsp_fixture_url"
  fi
  IFS=',' read -r -a transport_list <<<"$transports"
  if [[ "${#transport_list[@]}" -eq 0 ]]; then
    echo "STROK_LIVE_ACCEPTANCE_TRANSPORTS cannot be empty" >&2
    exit 1
  fi
  for transport in "${transport_list[@]}"; do
    if [[ "$transport" != "tcp" && "$transport" != "udp" ]]; then
      echo "unsupported RTSP transport in STROK_LIVE_ACCEPTANCE_TRANSPORTS: $transport" >&2
      exit 1
    fi
    run_trace "rtsp-${transport}-pressure" "$input" "$transport" 30 120
    run_trace "rtsp-${transport}-capped" "$input" "$transport" 5 0
  done
}

run_camera() {
  if [[ -z "$camera_input" ]]; then
    echo "STROK_CAMERA_INPUT is unset; camera trace not run" >&2
    return
  fi
  run_trace "camera-pressure" "$camera_input" auto 30 120
  run_trace "camera-capped" "$camera_input" auto 5 0
}

case "$requested_mode" in
  all)
    run_rtsp
    run_camera
    ;;
  rtsp)
    run_rtsp
    ;;
  camera)
    if [[ -z "$camera_input" ]]; then
      skip "STROK_CAMERA_INPUT must name a physical or loopback camera input"
    fi
    run_camera
    ;;
esac

printf 'live acceptance traces written to %s\n' "$output_dir"
