# Testing Kiwi

Run from the repository root. The product is the terminal application; tests
exercise internal models, native boundaries and user-visible behavior.

| Command | Dependencies | What it verifies |
| --- | --- | --- |
| `make test-core` | LuaJIT, standard shell utilities | Headless core suites plus CLI help/version/error paths. The runner disables `ffi.load` so installed graphics libraries cannot hide an accidental dependency. |
| `make check` | Documented native build dependencies and C compiler | Complete Lua suite, seeded parser fuzzing, real PTYs, C readiness watcher, terminfo contract, CLI behavior and syntax of every Lua file. |
| `make test-applications` | Native build, Bash, Zsh, Vim, Neovim, tmux, less, system top | Eight real-program workflows, independent saved-file assertions, job control, resize, parser diagnostics and chunk-invariant replay. No display is needed. |
| `make test-pty-watch` | C17 compiler, POSIX pthreads | One-shot notifications, no byte consumption, rearm, descriptor replacement, EOF and worker shutdown. |
| `make interaction-smoke` | Native build and a graphical desktop | Live splits, directional focus, divider resize, zoom, font reset, search and close through native action dispatch. |
| `make pty-wake-smoke` | Native build and a graphical desktop | Readable child output wakes the host before a deliberately long event timeout. |
| `make cocoa-smoke` | macOS desktop and native build | Private pasteboard, IME/accessibility bridges, menus, tabs, multi-window session movement, layout restore and development app launch. |
| `make release-check` | Packaging tools and native environment | Reproducible archives, checksums, metadata, extracted launcher and macOS app launch. |

Individual suites can be run without loading unrelated tests:

```sh
LUA_PATH='src/?.lua;src/?/init.lua;;' luajit src/kiwi/test.lua workspace interaction_actions
CFLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' make test-pty-watch
CFLAGS='-fsanitize=thread -fno-omit-frame-pointer' make test-pty-watch
CFLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' make test-file-watch
make configuration-reload-smoke
```

The runner sorts test names for repeatable failure order. A failed test stops
the run and returns nonzero. Unknown suite names are errors. The core target
is a fast subset; image decoding, font shaping and native hosts still require
the complete suite.

Shell-script tests report explicit skips for missing optional shells. CI installs
Bash, Zsh and fish and sets `KIWI_REQUIRE_SHELLS=bash,zsh,fish` in the primary
Linux/macOS checks. A required missing shell fails. Nushell is exercised where
installed, including the existing Intel compatibility job. Test subprocesses
record and validate exit status independently of LuaJIT's `io.popen():close()`
behavior. SSH helper tests use explicit local stubs and cannot fall back to the
user's real SSH client.

Graphical smokes are bounded and use controlled workloads. The new interaction
smoke disables saved-layout restore and persistence. The layout-restore smoke
uses a temporary layout path and a temporary default shell; explicit command
launches intentionally do not restore saved layouts. The host-wake smoke creates
one temporary window and does not touch the user's clipboard or workspace file.
The configuration-reload smoke owns temporary configuration/theme files and
drives automatic save, error/recovery and opt-out/manual-retry paths through a
real WGPU window, retaining the child output across reflow.

Linux graphical checks are in the existing self-hosted desktop qualification
workflow. Adding those gates is not evidence that they have run. The macOS
workflow includes interaction and host-wake gates on Intel and Apple Silicon.

## Interactive application regression gate

`make test-applications` starts programs in a temporary working/configuration
directory with isolated editor settings and dedicated tmux sockets. It fails
when a requested application is unavailable; there are no implicit skips.
For focused debugging after building native/terminfo dependencies:

```sh
KIWI_INTERACTIVE_APPS=vim,tmux-nvim ./script/test-applications
KIWI_INTERACTIVE_ARTIFACTS="$PWD/.build/application-trial" ./script/test-applications
```

The default eight workflows exercise Bash/Zsh line editing, Unicode paste,
resize and foreground-job interruption; Vim/Neovim Unicode insertion and
saved-file contents; Neovim inside tmux; tmux split/resize/zoom/close; less
search/page navigation; and system top filtered to its own process. Special
keys and paste pass through the application's encoders. Readiness is observed
from terminal output, saved files and foreground process groups, with bounded
deadlines. Vim runs in normal Vim mode (`-N`) with user configuration disabled.

Each case retains bounded input/output/resize JSONL, text checkpoints and a
machine-readable report in `.build/application-evidence`. Successful captures
must replay identically as whole chunks, individual bytes and eight seeded
chunkings, and match the live final state. Editor files provide an independent
input oracle. Reports include application versions, source revision/state,
byte counts, checkpoint counts and parser diagnostics. Elapsed time includes
replay verification and is not a terminal latency benchmark.

Vim's exact `DCS zz ST` and `CSI 0 % m` negative probes are explicitly counted
and retained as rejected controls, with at most one of each per case. Their
cursor/attribute preservation has deterministic split-boundary tests. Other
parser errors, ignored strings and unknown controls fail the gate. See the
[Vim probe source](https://github.com/vim/vim/blob/v9.1.1752/src/term.c#L4148).

CI installs the applications, runs the gate on Linux and both macOS
architectures, and uploads reports and controlled recordings even on failure.
Captures contain only these test sessions; they may include timestamps, process
IDs and temporary paths. This does not exercise physical keyboard layouts,
native input routing, IME, clipboard ownership, visual rendering, SSH, fish or
Nushell. Those remain independent qualification requirements.

## Evidence recorded during the 2026-10-25 application pass

Host: Intel x86_64, macOS 15.7.7 (24G720), LuaJIT, GLFW/Cocoa/Metal.

- `make test-core`: 261 tests across 51 suites, plus CLI checks.
- `make check`: 473 tests across 106 suites; 15 real PTY tests; parser fuzzing
  with 6 corpus inputs and 128 seeded cases; C watcher, terminfo and CLI checks;
  syntax validation of 300 Lua files, plus macOS application launcher C checks.
- C watcher passed AddressSanitizer + UndefinedBehaviorSanitizer and, separately,
  ThreadSanitizer.
- Live interaction smoke passed. Host-wake smoke observed output in approximately
  70 ms with a 2000 ms host timeout, including the child's deliberate 50 ms delay.
- Cocoa bridge, multi-window, session-move, layout-restore, toolbar, directory
  proxy and palette smokes passed. The staged app also passed the bounded native
  Apple-event action smoke when invoked directly. The development `.app` launched
  through LaunchServices, exited at its bounded deadline and removed its PID file.
- `make cocoa-smoke` and `make release-check` stop at the `sdp` dictionary check:
  this host has Command Line Tools but no full Xcode. The release check completed
  its two-archive byte comparison, checksum validation, extraction and release
  `--version` check before that stop. Neither aggregate gate is reported as passed.
- fish and Nushell were unavailable locally; their executable integration paths
  were explicitly skipped, not claimed as locally verified.

See the [daily-driver ledger](DAILY_DRIVER_COMPATIBILITY.md) for unresolved
application compatibility and manual desktop requirements. These checks do not
prove Windows support, screen-reader usability, Linux graphics qualification,
or performance superiority to another terminal.
