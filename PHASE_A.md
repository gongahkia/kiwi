# PHASE_A.md — Foundations & Scaffolding

**Goal:** A buildable, well-structured C++20 repo that opens the terminal, switches to raw mode + alternate screen, *always* restores cleanly (normal exit, signal, exception), detects size, and has CI. No rendering yet — this phase exists so every later phase has a safe place to run.

**Exit criteria:** clean build on ≥2 OSes in CI; raw-mode guard provably restores on normal exit, Ctrl-C, and uncaught exception; terminal size query + SIGWINCH working.

---

## Architecture decisions locked in this phase

- **Language:** C++20. Use `std::filesystem`, `std::span`, designated initializers, `<charconv>`.
- **Build:** CMake (≥3.20). Targets: the binary, plus a `tests` target later.
- **Decode:** FFmpeg/libav (Phase B). Linked via `pkg-config` (`libavformat libavcodec libavutil libswscale libswresample`). Document a minimum FFmpeg version (target FFmpeg 6.x+; the send/receive API has been stable since 3.1 but use a recent one).
- **Audio:** miniaudio (single-header, no system deps) — chosen in Phase D, but reserve the slot now.
- **CLI:** a small dependency (CLI11, header-only) or hand-rolled. Recommend CLI11 for speed of development; it's header-only so it doesn't complicate packaging.
- **Why C++ (recorded for posterity):** matches the lineage of `timg`/`chafa`, max throughput for per-frame pixel work; cost is manual memory management (mitigated by RAII everywhere) and harder distribution (mitigated in Phase G packaging).

## Suggested repo layout

```
<name>/
  CMakeLists.txt
  LICENSE                 # MIT
  README.md
  DEPENDENCIES.md
  BENCHMARKS.md
  .gitignore
  .github/workflows/ci.yml
  cmake/                  # find-modules if needed
  src/
    main.cpp              # CLI parse, wire, run loop, teardown
    cli.hpp / cli.cpp
    terminal.hpp / terminal.cpp   # raw mode, alt screen, size, SIGWINCH
    log.hpp / log.cpp
    # (later phases add decode/, render/, audio/, emit/)
  third_party/            # vendored single-headers (miniaudio, CLI11) if not system
  docs/                   # demo gifs, technique writeup
  tests/
```

## §CLI — argument parsing

Wire these now (stubs for unimplemented behavior, parsed and validated):

- positional `<input>` (file path / `cam` / URL — only file used until Phase B).
- `--width N`, `--height N`, `--fit`
- `--fps N`, `--max-fps N`
- `--mode {luminance|structure|halfblock}` (default luminance until E)
- `--color-mode {auto|truecolor|256|16|mono}` (default auto)
- `--charset NAME|string`
- `--edge-threshold`, `--dog-sigma`, `--contrast` (structure knobs, Phase E)
- `--dither {none|ordered|fs}`
- `--loop`, `--log FILE`, `--gpu`, `--export FILE`
- `--version`, `--help`

**DoD detail:** unknown flags and malformed values exit non-zero with a one-line message naming the offending flag. `--help` lists every flag with a one-line description.

## §RawMode — terminal raw mode (POSIX)

Use `termios` on POSIX. Pattern:

1. `tcgetattr(STDIN_FILENO, &orig)` — save original.
2. Copy to `raw`; disable canonical mode + echo: clear `ICANON | ECHO | ISIG?` — keep signals for now (we want Ctrl-C to trigger teardown), or disable `ISIG` and handle keys manually; document the choice. Also clear `IXON`, `ICRNL` as needed for key handling.
3. `tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)`.
4. Write enter-alt-screen `\e[?1049h`, hide cursor `\e[?25l`.

Wrap **all** of this in a `TerminalSession` RAII class. Destructor: show cursor `\e[?25h`, leave alt screen `\e[?1049l`, `tcsetattr(..., &orig)`. The destructor must be idempotent and `noexcept`.

**Windows note (optional in A, required if Windows targeted in G):** enable virtual terminal processing via `SetConsoleMode(ENABLE_VIRTUAL_TERMINAL_PROCESSING)` and use the Console API for raw input. Keep this behind a platform abstraction.

**DoD:** run the program, press Ctrl-C, confirm the shell returns to normal (cursor visible, echo on, main screen restored, no leftover escape garbage).

## §Teardown — signal & panic safety

The terminal **must** be restored on every exit path:

- **Normal return:** RAII destructor handles it.
- **Signals (SIGINT, SIGTERM, SIGHUP):** install handlers that set an atomic "should-quit" flag the main loop checks; the loop then returns and the RAII destructor runs. Avoid doing complex work in the handler (async-signal-safety) — set a flag, optionally write the minimal restore sequence directly with `write()` if you must restore from within the handler.
- **Uncaught exception:** wrap `main`'s body in try/catch; the `TerminalSession` destructor runs during stack unwinding before the catch logs the error. Verify by throwing deliberately.
- **`std::terminate`/abort paths:** as a backstop, register an `atexit`/`std::set_terminate` that writes the restore escape sequence.

**DoD:** SIGINT, SIGTERM, and a thrown exception each leave the shell clean.

## §Size — terminal dimensions + SIGWINCH

- Query via `ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws)` → `ws_col`, `ws_row` (and `ws_xpixel`/`ws_ypixel` when available — useful later for true cell pixel size).
- Install a SIGWINCH handler that sets an atomic "resized" flag; the main loop re-queries size when the flag is set (don't query in the handler).
- Expose `TerminalSize { int cols, rows; int xpixel, ypixel; }`.

**DoD:** program prints size; resizing updates it live without busy-polling.

## §Logging

- Logging must never write to the rendered alt-screen. Default: silent. `--log FILE` opens a log sink; levels (error/warn/info/debug).
- Provide a tiny `LOG_*` macro set; no heavyweight logging dependency.

**DoD:** `--log` captures diagnostics; without it, stderr/screen stay clean.

## §CI

`.github/workflows/ci.yml`: build on `ubuntu-latest` and `macos-latest`; install FFmpeg dev libs via apt/brew; configure with warnings-as-errors; build; run any tests. Windows job optional/allowed-to-fail initially. Badge in README.

## Tasks (mirror of TODO Phase A, with hints)

- A1 repo/license/README — keep README honest about pre-alpha status.
- A2 name — run the searches; record alternatives considered.
- A3 CMake — set `CMAKE_CXX_STANDARD 20`, `CMAKE_CXX_STANDARD_REQUIRED ON`; add a `Werror` build profile.
- A4 DEPENDENCIES.md — pkg-config snippet for the av libs; min versions; how to install on Ubuntu/macOS.
- A5 CLI — CLI11 wiring; validate enums.
- A6 RawMode — the `TerminalSession` RAII class.
- A7 Teardown — signal flag + try/catch + terminate backstop.
- A8 Size — ioctl + SIGWINCH.
- A9 Logging.
- A10 CI matrix.
- A11 BENCHMARKS.md template.

## Common pitfalls
- Forgetting `TCSAFLUSH` leaves input buffered/echoed.
- Doing non-async-signal-safe work in signal handlers → deadlocks/crashes. Use a flag.
- Not restoring on exception → garbled shell that scares users on first run.
- Hardcoding 80×25 instead of querying → wrong aspect from the start.
