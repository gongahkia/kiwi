#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/target/screencast"
WATCH_FILE="$WORK/watch-mode.mmd"
SERVER_PID=""
WATCH_PID=""

cleanup() {
  if [[ -n "$WATCH_PID" ]]; then
    kill "$WATCH_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

mkdir -p "$WORK"
cd "$ROOT"

say() {
  printf "\n\033[1;36m%s\033[0m\n" "$1"
}

prompt() {
  printf "\n\033[1;32m$ %s\033[0m\n" "$1"
}

write_watch_source() {
  local mode="$1"
  case "$mode" in
    first)
      cat > "$WATCH_FILE" <<'MMD'
%%{ animate: 'trace', speed: 1.25, loop: true }%%
graph LR
  Edit[edit Mermaid] --> Watch[kumeyuri watch]
  Watch --> Text[redraw terminal frame]
MMD
      ;;
    second)
      cat > "$WATCH_FILE" <<'MMD'
%%{ animate: 'trace', speed: 1.25, loop: true }%%
graph LR
  Edit[edit Mermaid] --> Watch[kumeyuri watch]
  Watch --> Text[redraw terminal frame]
  Watch --> SVG[render SVG for docs]
MMD
      ;;
    third)
      cat > "$WATCH_FILE" <<'MMD'
%%{ animate: 'trace', speed: 1.25, loop: true }%%
graph LR
  Edit[edit Mermaid] --> Watch[kumeyuri watch]
  Watch --> Text[redraw terminal frame]
  Watch --> SVG[render SVG for docs]
  SVG --> Embed[web embed]
MMD
      ;;
  esac
}

say "kumeyuri: Mermaid, animated, anywhere text renders"
sleep 3

say "1/3 CLI render"
prompt "cargo run -q -p kumeyuri-cli -- render demos/sorting-algorithm-trace.mmd --format text --theme github --charset unicode --width 96"
cargo run -q -p kumeyuri-cli -- render demos/sorting-algorithm-trace.mmd --format text --theme github --charset unicode --width 96
sleep 6

say "2/3 watch mode redraw"
write_watch_source first
prompt "cargo run -q -p kumeyuri-cli -- watch target/screencast/watch-mode.mmd"
cargo run -q -p kumeyuri-cli -- watch "$WATCH_FILE" &
WATCH_PID="$!"
sleep 6
say "editing source: add SVG output"
write_watch_source second
sleep 7
say "editing source: add web embed"
write_watch_source third
sleep 7
kill "$WATCH_PID" >/dev/null 2>&1 || true
wait "$WATCH_PID" 2>/dev/null || true
WATCH_PID=""
sleep 3

say "3/3 web embed"
prompt "python3 -m http.server 4187 --bind 127.0.0.1 --directory site"
python3 -m http.server 4187 --bind 127.0.0.1 --directory site > "$WORK/site.log" 2>&1 &
SERVER_PID="$!"
sleep 3
prompt "node -e 'verify playground renders via WASM'"
node -e 'import("playwright").then(async ({ chromium }) => { const browser = await chromium.launch(); const page = await browser.newPage({ viewport: { width: 1280, height: 800 } }); await page.goto("http://127.0.0.1:4187/", { waitUntil: "networkidle" }); await page.waitForSelector("#playground-output svg", { timeout: 10000 }); const text = await page.locator("#playground-status").textContent(); const frames = await page.locator("#playground-output svg g").count(); console.log(`web embed ok: ${text}; svg groups=${frames}`); await browser.close(); })'
sleep 5
kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

say "done: CLI render + watch mode + web embed"
sleep 18
say "recording complete"
