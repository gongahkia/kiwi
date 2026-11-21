# Arch laptop qualification — 2026-11-21

This records the requested Bash integration repair, laptop baseline, Linux
desktop work and measured reload optimization. Raw reports are retained beside
this document, including failed attempts. Report source states are preserved:
some functional probes exercised pending changes and explicitly say `dirty`;
accepted relative timing comparisons use clean revisions. No hosted CI or
other-machine qualification is claimed.

Raw transcripts preserve captured bytes, including trailing whitespace. A
whole-bundle whitespace check flags five such transcript lines; source,
documentation and JSON whitespace checks exclude raw logs and pass. The
original invalid text report is also retained without rewriting its bytes.

## Machine and build

Omarchy Linux x86_64, kernel 7.2.15-1-omarchy, Intel i7-1355U and Iris Xe
(RPL-U), Mesa/Vulkan Intel 26.2.5. Installed packages include LuaJIT
2.1.1792588164+a4c0645-1, GLFW 3.5.1, GTK 4.24.1, libadwaita 1.10.0,
Sway 1.12, wtype 0.4, IBus 1.5.34, ibus-libpinyin 1.16.5, Lua 5.5.1,
AT-SPI 2.62.1 and Orca 51.1. WGPU is the repository's pinned v29.0.1.1.
The actual Vulkan adapter identity is recorded in each interactive report.
Software-Vulkan functional tests are identified separately below.

Build with `make native gtk-host terminfo`. CPU benchmarks run with
`LUA_PATH='src/?.lua;src/?/init.lua;;'`. Dependencies were installed through
the system package manager. No persistent desktop configuration was edited.
The user accessibility service was restarted once after its advertised socket
refused connections; direct D-Bus queries and new GTK clients subsequently
connected. Existing applications' reconnection was not qualified.

## Changes and root causes

| Change | Main revision | Evidence |
| --- | --- | --- |
| Bash indexed-array `PROMPT_COMMAND` support | `f318630d` | Preserves scalar/array hooks and ordering, sparse indices, exported state and uninstall/reinstall; unsupported or read-only declarations remain inactive. Regression tests include execution by Bash's actual prompt engine. Plain `make check` passes without bypassing Arch startup configuration. |
| Surface acquisition resize recovery | `105e184d` | The appearance smoke reproduced a WGPU abort: a scissor rectangle exceeded a target resized during frame acquisition. Abort that unencoded frame and retry pane layout against the new surface size. Shrink/grow regression and graphical smoke pass. |
| GTK child-surface fractional scale | `99787e90` and preceding `8d80f529` | Observe the WGPU child surface's preferred fractional scale; validate listener setup and destroy it with its owner. GTK GL retains its documented integer buffer scale. See ADR 0051. |
| History benchmark accounting | `8b0ab3c8` | Startup resize had already retained six rows before traffic counting. Record that initial occupancy separately and require `initial + pushed = retained + evicted`. Capacity, eviction, duration, memory and responsiveness gates remain enforced. |
| Idle interval observation | `e1bb4ad0` | Begin recording after a ready frame, hidden cursor and 300 ms of stable geometry; a second real PTY handshake starts the quiet interval. Later resizing fails the test. Production scheduling is unchanged. |
| Current accessibility and IME fixtures | `b1a54452`, `3753c0e4`, `ff72d3be` | Own the AT-SPI registry, handle current status properties and Orca CLI/log formats, and isolate IBus services before D-Bus activation. Use unmodified system libpinyin resources. |
| Compact reflow and copy | `cc20ef01`, `9bd7a75b` | Keep retained history packed while rewrapping, expand only visible rows, and copy packed array slots directly. Source/candidate isolation and cell representation are tested. |
| Benchmark session ownership | `dc217c35`, `dda1932d` | Own Sway and its runtime; reject attached input devices; distinguish nested and offscreen hardware scopes. The application input guard remains active. |
| X11 selection fixture | `09de1a58` | Xvfb alone left GLFW on the inherited Wayland display. Unset that display and select X11 before the private clipboard/PRIMARY tests. Both GLFW and GTK checks pass. |
| Valid UTF-8 text corpus | `08fad759` | Correct the malformed combining fixture, version it as corpus v2 and require valid decoding and an exact byte round trip for every scenario. |

`8d80f529` and `eab1b9fb` were user-created `work~` commits containing concurrent
work from this session; they were preserved. Other commits separately repair
resize-sensitive pixel readback, hints fixtures, startup geometry measurement
and native pointer-motion classification. No default host was changed.

## Verification

`make check` passed **709 Lua tests across 135 suites**, seeded parser fuzzing,
19 real PTY tests, native readiness/file/process checks, the real-PTY benchmark
harness and trial lifecycle checks, regression budgets, 5,000 POSIX regex oracle
cases, terminfo, CLI behavior and syntax for 388 Lua files. The core-only run
passed 462 tests. Nushell integration was skipped because `nu` is absent;
Cocoa accessibility was skipped because this laptop is Linux.
[Full transcript](full-check.log), [core transcript](core-check.log).

All eleven local application cases and six authenticated loopback SSH cases
passed again after the final cell-copy change. These include Bash, Zsh, fish,
Vim, Neovim, tmux, tmux/Neovim, less, top and combined workflows, with saved-file,
resize, job-control and chunk-invariant replay assertions.
[Local report](applications-final.json), [SSH report](ssh-final.json).

Native GLFW/Wayland checks passed for interaction, GPU allocation rollback,
finite/indefinite PTY wake, appearance/shaders/resize, search, vi, selection,
URL hints, colour glyphs and underline readback. Configuration reload passed
again after the final optimization, including visible PTY history and rejected
resource recovery. Actual X11 readback and PRIMARY checks used Xvfb with the
inherited Wayland display removed.
[Graphical transcript](graphical-glfw.log),
[reload transcript](application-reload-final.log),
[GLFW PRIMARY](primary-x11-glfw.log), [GTK PRIMARY](primary-x11-gtk.log).

GTK Wayland PRIMARY checks passed with independent clients, real PTY input,
WGPU, GL and native tabs, using software Vulkan on private headless Sway.
[Transcript](gtk-primary-wayland.log).
Virtual fractional/integer scaling, output moves/removal/power and process
pause/recovery passed on both presenters. WGPU follows preferred fractional
scale; GL rounds its buffer scale as documented.
[WGPU transitions](transitions-wgpu.json), [GL transitions](transitions-gl.json).
These reports mark pending source changes as dirty. They exercise virtual
outputs and SIGSTOP/SIGCONT, **not physical monitor changes or system sleep**.

Real system IBus/libpinyin composition, Unicode commit, cancellation, Kitty
encoding, Find, Ctrl-C and focus-return checks pass on WGPU and GL with clean
source and unmodified system engine resources.
[WGPU IME](ime-wgpu.json), [GL IME](ime-gl.json).
An [initial failed attempt](ime-initial-failure.log) included a real Lua 5.5
resource warning and service-isolation problems. The warning was initially
suspected to block composition; later stock-resource passes disproved that
necessity. A temporary private resource override was removed. The initial
failure's precise composition cause remains unverified.

External AT-SPI consumers passed text/range/caret/selection/event/focus queries
on both Wayland presenters. Real Orca commands generated the expected Unicode
line, palette title and exact selected text on a private X11 desktop.
[Wayland WGPU](atspi-wayland-wgpu.json), [Wayland GL](atspi-wayland-gl.json),
[Orca WGPU](orca-wgpu.json), [Orca GL](orca-gl.json).
The GL report exercised pending fixture changes and says dirty; WGPU has a
clean-source pass. A later clean-source GL retry
[timed out querying `orca --version`](orca-final-metadata-timeout.log) before
starting the qualification, and is not counted as a pass. Audio, braille,
physical keyboard layouts and everyday screen-reader usability are unverified.

## Interactive baseline and idle gates

Two final batches each used five fresh processes per mode and forty measured
inputs per process, for **800 acknowledged inputs across twenty processes**.
Source was clean `9bd7a75b`, Intel Vulkan, nested Sway/GLES2, 72 × 20 cells.
The workload is synthetic input callback → real PTY numbered reply → parser →
successful WGPU presentation return. It excludes hardware keyboard delivery,
IME, GPU completion, display feedback and panel scan-out.

| Median of independent trial metrics | Final A | Final B |
| --- | ---: | ---: |
| Idle input p95 | 7.91 ms | 6.08 ms |
| Saturated ASCII input p95 | 38.22 ms | 37.94 ms |
| Idle child-ready presentation | 424.2 ms | 400.6 ms |
| Saturated child-ready presentation | 440.5 ms | 395.1 ms |

All six existing relative gates passed; no thresholds were changed.
[A](interactive-final-a.json), [B](interactive-final-b.json),
[budget results](interactive-repeatability-final.json).
The earlier [A](interactive-before-a.json)/[B](interactive-before-b.json)
pair also passed, at 44 × 20 cells. Different geometries exclude a direct
before/after optimization comparison between those groups.

After the accessibility-bus repair, quiet-window gates passed at six GLFW
wakes in 2.994 s and eleven GTK wakes in 2.981 s, each entering five indefinite
waits. The limit remains thirty wakes. This counts host-loop wakes; it does
not measure battery or package/GPU energy.
[GLFW](idle-glfw.json), [GTK](idle-gtk.json).
The [original failed idle report](idle-startup-failure.json) included startup
allocation/animation and is retained; the observation boundary changed, not
the production scheduler.

## Sustained history

The hardware GLFW nested-Wayland run passed 120 measured acknowledgements over
a 611.1-second retained interval with 2,000 retained rows. First-input-to-end
counts, including warmup, were 3,021,887 pushes and 3,019,893 evictions, with six
initially retained rows. Peak sampled RSS was 200.9 MiB; quarter-median RSS grew
1.01 MiB and post-collection retained Lua heap grew 0.56 MiB. Acknowledgement
p95 was 86.64 ms and maximum 105.25 ms, within the two-second ceiling.
[Complete report](history-glfw-2000.json).

The [earlier counter failure](history-glfw-counter-failure.json) is not a
retention failure or accepted baseline. Its startup rows were missing from the
accounting identity; the corrected measurement has a real startup-history
regression and preserves the budgets.

The first 10,000-row GTK nested run was
[invalidated by external key input](history-gtk-input-invalid.json) after 24
measured acknowledgements. This is not a completed soak. The launcher now
detaches compositor input devices, verifies that no seat owns devices, and
records `native_input_scope`. An owned headless parent with real virtual-keyboard
injection verified that parent keys did not reach Kiwi while its native guard
remained enabled. [Injection evidence](input-isolation.log),
[preflight report](input-isolation-preflight.json).

The final offscreen GTK/10,000-row run passed 120 measured acknowledgements
over a 627.0-second retained interval. Source was clean `dda1932d`, with the
actual Intel Vulkan adapter and `headless-wayland-gles2` scope. It retained
10,000 rows, counted 1,202,375 pushes and 1,192,375 evictions after first input,
and observed 477.4 MiB sampled peak RSS. Quarter-median RSS decreased 12.22 MiB;
post-collection retained heap grew 0.65 MiB. Acknowledgement p95 was 490.57 ms
and maximum 711.74 ms. All original duration, history, 64 MiB RSS-growth,
16 MiB retained-heap-growth, 1 GiB RSS and two-second response gates passed.
[Complete GTK report](history-gtk-10000-headless.json).

The user was running other work during this qualification; its timing is not
an idle-machine performance comparison. Different history capacity, host,
geometry and display scope exclude a direct speed comparison with GLFW.

## Reload optimization

The original all-size baseline found 10,000-line font staging at 879.8 ms p95
and 320.9 MiB sampled transient Lua heap, whereas palette staging was 11.8 ms.
That selected reflow allocation as the optimization target.
[Original report](reload-original.json).

The naive packed-history change halved heap but worsened font staging to
1,432.6 ms. Profiling showed substantial interpreted compact-cell field access.
The final change copies stored array slots directly while preserving optional
fields, independent mutable cells and shared immutable codepoint arrays.
[Naive report](reload-naive-packed.json), [naive profile](profile-naive.txt),
[final profile](profile-final.txt).

Sequential clean A/B/A/B runs used the same 10,000-line-only command, five
staging iterations per fresh process:

| Run | Font wall p95 | Peak Lua heap delta | Sampled process RSS |
| --- | ---: | ---: | ---: |
| Baseline A (`3753c0e4`) | 948.4 ms | 272.3 MiB | 460.0 MiB |
| Candidate B (`ff14dca0`, worktree equivalent of `9bd7a75b`) | 376.6 ms | 163.8 MiB | 330.8 MiB |
| Baseline A2 | 673.3 ms | 272.0 MiB | 458.2 MiB |
| Candidate B2 | 357.1 ms | 162.9 MiB | 330.1 MiB |

[A](reload-baseline-a.json), [B](reload-candidate-b.json),
[A2](reload-baseline-a2.json), [B2](reload-candidate-b2.json).
The spread in baseline timings limits precision; these are two processes per
revision, not a statistical population claim.

A further matched all-size command measured 10,000-line staging at 1,055.5 →
442.6 ms p95, heap delta 320.2 → 162.8 MiB and sampled RSS 525.6 → 357.1 MiB.
These CPU/native-font measurements exclude GPU allocation/upload/presentation
and PTY resize. Full-GC endpoints check retained state separately from transient
heap. The allocation regression fails before the change and also verifies that
retained cells stay packed, visible cells are ordinary mutable tables and the
original state remains unchanged.
[All-size baseline](reload-baseline-all.json),
[final](reload-final-all.json), [allocation failure](reflow-allocation-before-failure.log),
[focused pass](reflow-focused.log).

Ordinary mixed long-run batch p95 changed from 23.50 to 27.65 ms; navigation
changed from 4.48 to 4.69 ms. Both pass the existing 25% CPU/15% memory gates.
No general write/history speedup is claimed. The optimization claim is limited
to the measured font-reload staging workload.
[Before](longrun-before.json), [final](longrun-final.json).
The [existing long-run budget checker passed](longrun-budget.log); its CPU
threshold was not changed to accommodate the observed variation.

Evidence validation also found malformed UTF-8 in the shared combining-text
fixture. The [original text report](text-before.json.invalid-utf8) is preserved
byte-for-byte and is not accepted as machine-readable baseline evidence.
The corrected fixture contains valid combining marks and declares corpus
version `kiwi-text-corpus-v2`. A decoding/round-trip regression fails on the
old bytes. Do not compare the changed combining workload against corpus v1.
The [final corpus-v2 text report](text-final.json) passes strict UTF-8/JSON
validation; the malformed original is not used for a relative comparison.

## Remaining qualification and next work

The user has only the laptop display and explicitly deferred further sleep
checks while running other work. They reported a responsive Kiwi after sleep,
but the armed observer recorded no new CLOCK_BOOTTIME/CLOCK_MONOTONIC gap or
matching kernel transition before the window closed. That result remains
[incomplete](suspend-incomplete.json), not a suspend failure in Kiwi.
The [negative control](suspend-negative.json) correctly fails without sleep.

When available, run `./script/suspend-smoke --host glfw --report /tmp/suspend.json`
and wait for its readiness message before initiating system sleep manually;
repeat with `--host gtk`. It requires a fresh real PTY/frame/geometry reply and
does not initiate suspend. Physical monitor hotplug remains unverified because
no external monitor is available. Virtual output tests do not close that gate.

Prioritize GTK/WGPU for the next Linux desktop qualification work: it has the
composition and Wayland PRIMARY mechanisms exercised here. Qualify physical
recovery, real clipboard exchange and everyday accessibility before deciding
whether to make it the supported default. The current default GLFW/Wayland
path still lacks an IME composition bridge and its PRIMARY implementation is
X11-only. This work does not close those default-host gaps or claim terminal
parity. Candidate-window placement, other IMEs/compositors, physical fractional
scale transitions, macOS and Windows remain outside this laptop evidence.

## Repeatable commands

```sh
make check
make test-applications test-ssh-applications
make interaction-smoke configuration-reload-smoke appearance-smoke hints-smoke
./script/primary-selection-smoke
KIWI_HOST=gtk ./script/primary-selection-smoke
./script/idle-wake-smoke --report bench/results/idle-glfw.json
KIWI_HOST=gtk ./script/idle-wake-smoke --report bench/results/idle-gtk.json
./script/bench-nested-wayland --trials 5 --samples 40 --report bench/results/a.json
./script/bench-nested-wayland --trials 5 --samples 40 --report bench/results/b.json
./script/check-interactive-budget bench/results/a.json bench/results/b.json
WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128 KIWI_HOST=gtk \
  ./script/bench-nested-wayland --headless --mode saturated --traffic styled-unicode \
  --trials 1 --samples 120 --warmup 5 --soak-seconds 600 --scroll-mode history \
  --scrollback-limit 10000 --heap-measurement retained --report bench/results/history-gtk.json
make bench-write bench-burst bench-text bench-longrun bench-configuration-reload
```

Use a quiet machine for relative performance comparisons. Match actual adapter,
driver/runtime, geometry, workload, clock, display/input scope and sample
schedule. `check-interactive-budget` refuses incompatible conditions and dirty
source. Run on battery and AC separately if power behavior is the question;
these reports establish neither battery consumption nor keyboard-to-panel latency.
