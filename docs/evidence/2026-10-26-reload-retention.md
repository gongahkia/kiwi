# Configuration snapshot retention, 2026-10-26

Implementation: `ed32438`. Benchmark diagnostics: `2da812d`.
Graphical fixture readiness: `9767936`.

The existing benchmark failed before any optimization: after five rejected font
reloads with 10,000 history lines, retained Lua heap exceeded the post-warmup
baseline by **332,866 KiB**, against the unchanged **4,096 KiB** ceiling.
The [failure log](2026-10-26-reload-retention-before.txt) comes from `9e35740`
with only the diagnostic output subsequently committed as `2da812d`.

Weak-value probes identified candidate states retained after their plans,
transactions, fonts and renderers disappeared. With JIT disabled, the same
diagnostic collected the candidates. With JIT enabled, `jit.util.tracek` exposed
function constants whose upvalues reached those states; flushing traces after
the failed diagnostic released them. Neither disabling nor flushing JIT is part
of the fix or acceptance tests. The [design decision](../adr/0047-reload-callback-lifetimes.md)
describes the explicit-context replacement.

Five new tests cover candidate collection after palette, full-reflow,
height-only and fast-width rejection, plus successful adoption. They also check
original-state identity, retained history and subsequent terminal output. The
new suite [fails against the old implementation](2026-10-26-reload-retention-regression-before.txt).
It runs first in both full and core tests, with normal JIT compilation enabled.

## Current measurements

Both reports use committed revision `9767936`, one warmup and five measured
iterations per case, with 0, 2,000 and 10,000 history lines in that order. Native
fonts, shaping and CPU buffer preparation are real; GPU work, presentation and
PTY resizing are excluded. RSS is sampled, not the OS high-water mark. Heap
retention is measured after collection relative to each warmed case. These
small samples establish a regression check, not a terminal speed ranking.

| Host, 10,000 lines | Palette wall p95 | Font resize wall p95 | Font retained heap | Font sampled peak process RSS |
| --- | ---: | ---: | ---: | ---: |
| macOS Intel, Darwin 24.6 | 9.9 ms | 671.6 ms | 51.4 KiB | 838.5 MiB |
| Ubuntu 24.04 x86_64 container | 13.5 ms | 609.4 ms | 71.8 KiB | 749.2 MiB |

All sizes/modes pass the existing 4 MiB retention ceiling. Raw metadata and
phase measurements: [macOS](2026-10-26-macos-reload-retention.json),
[Linux](2026-10-26-linux-reload-retention.json). macOS uses the Intel i5-8279U
host; Linux runs in its owned 2-CPU/4-GiB container. They are separate environments,
not a controlled platform comparison. A first Linux run completed measurements
but could not write its report because the archived results directory was
root-owned; the recorded run follows correction of that directory's ownership.

Font reloads still allocate approximately **341 MiB of additional Lua heap** at
10,000 lines. The retained-snapshot fix does not remove simultaneous old/new
history storage or establish acceptable interactive latency. No before/after
speedup is claimed: the baseline failed its memory gate and produced no complete
timing report. Broader startup, input latency, memory, idle power and desktop
qualification remain open.

## Verification and fixture correction

- macOS and Linux: 652 full tests / 128 suites; 412 core tests / 70 suites with
  native loading disabled. `make check` also passes fuzzing, PTYs, readiness,
  file watching, process metrics, regex oracle, terminfo and syntax gates.
- Linux Xvfb/software rendering: WGPU configuration smoke and GTK GL single-page
  and native-tab transactional reload fixtures pass.
- macOS Metal: WGPU configuration smoke passes, including shader failure/recovery
  and retained PTY history.

The first macOS graphical run failed because the test assumed the child had
filled scrollback within 0.5 seconds; an unchanged retry passed. The fixture now
waits for an OSC title marker emitted after the child's 200 history lines. Its
30-second deadline remains, and PTY readiness drives the wait. Both hosts pass
with `KIWI_RELOAD_CHILD_DELAY=2`, deliberately exceeding the former assumption.
This is a test scheduling correction, not evidence of physical keyboard/display
latency or actual-desktop reliability.
