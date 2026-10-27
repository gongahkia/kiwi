# Scrolling allocation and native CPU profile, 2026-10-27

The [native GTK/WGPU profile](2026-10-27-history-linux-gtk-profile-180.log) ran at
clean `9192e9a` in the owned Ubuntu 24.04 container (two CPUs, 4 GiB), private
Xvfb and Mesa llvmpipe. The external launcher invoked `luajit -jp=vf`, using
LuaJIT's default 10 ms sampling interval and 3% display cutoff. This wrapper
is not recorded by Git cleanliness or the report's compiler-flags field.
No other Kiwi build, test or benchmark ran concurrently; shared workstation
load and thermals were uncontrolled.

The [report](2026-10-27-history-linux-gtk-profile-180.json) completed all 40
measured inputs over 195.83 post-warmup seconds. Input p95 was 640.65 ms and
maximum 992.37 ms. RSS quarter-median growth was 1,064 KiB, heap growth
12,806.07 KiB and sampled peak RSS 659,268 KiB. Existing absolute gates passed.
This instrumented run does not explain every earlier timeout or establish a
repeatable performance baseline.

The profile attributed 43% of samples to C code, 32% to compiled Lua, 19% to
garbage collection and 5% to interpreted Lua (rounded percentages). Within
the GC samples, 22% occurred at `new_row` and 13% at `pack_row`; these are
allocation sites where collection ran, not an attribution of all collected
objects to those functions. Within C-code samples, 90% were at the presentation
closure in `context.lua`. Sampling does not distinguish GPU execution, driver
work and waiting inside that closure.

## Row storage change

Previously, scrolling a row into history allocated packed copies of every cell,
discarded its former live cells and allocated another complete blank screen row.
The updated path detaches the live cell array while history receives independent
packed cells, then resets and reuses the live cells. Discarded rows in scrolling
regions, the alternate screen and zero-history configurations can reuse their
cells directly. Row metadata and line identifiers are still freshly created;
command/image retention callbacks run before resetting cells. A generic screen
preserver returning nil still receives fresh replacement storage.

An isolated Intel macOS allocation probe warmed 500 upward scrolls on an 80×24
state, collected garbage, then measured 1,000 scrolls with GC stopped. History
capacity was either zero or 256 rows. It measured transient Lua allocation,
not retained memory or native latency:

| History rows | Previous code, KiB | Reuse, JIT enabled, KiB | Reuse, JIT disabled, KiB |
| ---: | ---: | ---: | ---: |
| 0 | 21,421.88 | 601.56 | 664.06 |
| 256 | 32,050.68 | 12,300.73 | 12,360.99 |

The regression test allows 2 MiB without history and 16 MiB with history. It
restores GC even if an assertion fails. Against the previous modules it fails
at 21,422.09 KiB; the updated module passes with JIT enabled and disabled.
Additional tests exercise styled wide/combining Unicode, hyperlinks, retained
and evicted history isolation, staged-state isolation, both scroll directions,
partial regions, fresh line identifiers and cleared command/image metadata.

These allocation figures do not establish a whole-application speedup. Native
follow-up must retain the original latency and memory gates.

`make check` passed on Intel macOS after the change: 684 deterministic Lua tests
across 132 suites, 19 PTY integration tests, native watcher/metrics fixtures,
interactive benchmark and budget checks, regex oracle, terminfo, CLI and syntax
checks. The targeted cell suite also passed with JIT disabled.

At clean `0c3cf81`, Linux passed 442 core tests across 74 suites with native
loading disabled, all [11 local application workflows](2026-10-27-row-reuse-applications.json)
and all [six loopback SSH workflows](2026-10-27-row-reuse-ssh.json). These include
the combined shell/editor/pager and tmux workflows, resize, saved-file assertions
and chunk-invariant replay. They establish PTY/parser/state behavior, not native
presentation performance.

## Ordinary native follow-up

The [requested 600-second run](2026-10-27-history-linux-gtk-row-reuse-warmup-failure.json)
at clean `0c3cf81` used the ordinary interpreter invocation with neither the
profiler nor trace callbacks. It failed during warmup sequence 6, after
2,263.52 ms, before any measured input samples. The input reached the PTY after
20.75 ms; two 4 KiB reads used 625.41 ms parsing, 784.70 ms preparing frames and
317.72 ms rendering. Parsing used 544.29 ms process CPU, preparation 783.31 ms
and rendering 679.95 ms (including worker threads). The acknowledgment had
not yet been parsed when the deadline check fired. Startup was 5.71 seconds.

History retained 10,000 rows after 7,499 evictions. Sampled peak RSS was
637,356 KiB, but there is no post-warmup memory-growth evidence. The allocation
fix therefore does **not** qualify sustained responsiveness. Both the earlier
trace-counter and profiler runs completed; ordinary runs have failed. These
separate shared-host trials do not prove instrumentation causes the difference,
or establish whether this failure involved a trace-cache flush. Further runtime
diagnostics are required; no latency or memory threshold was changed.
