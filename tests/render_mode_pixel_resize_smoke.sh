#!/usr/bin/env bash
set -euo pipefail

bin="${1:?contourtty binary required}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg CLI unavailable; skipping pixel resize smoke"
  exit 77
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 unavailable; skipping pixel resize smoke"
  exit 77
fi

tmp="${TMPDIR:-/tmp}/contourtty-pixel-resize-$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

input="$tmp/input.mp4"
log="$tmp/pixel.log"
transcript="$tmp/pixel.typescript"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i testsrc2=duration=3:size=1280x720:rate=6 \
  -frames:v 18 -pix_fmt yuv420p -y "$input"

python3 - "$bin" "$input" "$log" "$transcript" <<'PY'
import fcntl
import os
import select
import signal
import struct
import sys
import termios
import time

binary, input_path, log_path, transcript_path = sys.argv[1:]

def set_winsize(fd, rows, cols):
  fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

master, slave = os.openpty()
set_winsize(slave, 12, 40)
pid = os.fork()
if pid == 0:
  os.setsid()
  if hasattr(termios, "TIOCSCTTY"):
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
  os.dup2(slave, 0)
  os.dup2(slave, 1)
  os.dup2(slave, 2)
  os.close(master)
  os.close(slave)
  env = os.environ.copy()
  env["TERM"] = "xterm-kitty"
  env["TERM_PROGRAM"] = "Ghostty"
  env["COLORTERM"] = "truecolor"
  env.pop("NO_COLOR", None)
  os.execvpe(binary, [
    binary,
    "--render-mode", "pixel",
    "--caps", "kitty",
    "--fps", "6",
    "--bandwidth-cap", "1000",
    "--log", log_path,
    input_path,
  ], env)

os.close(slave)
started = time.monotonic()
deadline = started + 8
resized = False
quit_sent = False
with open(transcript_path, "wb") as transcript:
  while time.monotonic() < deadline:
    now = time.monotonic()
    if not resized and now - started >= 0.5:
      set_winsize(master, 16, 50)
      os.kill(pid, signal.SIGWINCH)
      resized = True
    if resized and not quit_sent and now - started >= 1.0:
      os.write(master, b"q")
      quit_sent = True
    ready, _, _ = select.select([master], [], [], 0.05)
    if ready:
      try:
        chunk = os.read(master, 65536)
      except OSError:
        chunk = b""
      if not chunk:
        break
      transcript.write(chunk)
    finished, status = os.waitpid(pid, os.WNOHANG)
    if finished:
      sys.exit(os.waitstatus_to_exitcode(status))
  try:
    os.kill(pid, signal.SIGTERM)
  except ProcessLookupError:
    pass
  _, status = os.waitpid(pid, 0)
  raise SystemExit(os.waitstatus_to_exitcode(status) or 124)
PY

grep -q "terminal caps .*kitty_graphics=true" "$log"
grep -q "render mode pixel protocol=kitty" "$log"
grep -q "resize reset render state terminal=50x16" "$log"
grep -q "playback quit before eof" "$log"
