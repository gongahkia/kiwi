# Native retained-heap investigation, 2026-10-27

The ordinary [600-second shaping-cache run](2026-10-27-shape-reuse.md) passed
its input-response and RSS gates but failed the sampled Lua heap-growth gate.
A subsequent headless parser/layout diagnostic retained only 132 KiB more heap
across 60,000 additional lines. To test the full native application, a separate
[diagnostic launcher](2026-10-27-native-retention-wrapper.lua) wrapped the first
full-history post-warmup resource observation and the final observation. Each
checkpoint forced one complete collection while the application, renderer and
10,000 history rows were still live. The normal collector remained enabled
between checkpoints. The launcher printed pre/post heap and collection cost.

This wrapper was external to the repository and is **not recorded by the raw
report's source-cleanliness or runtime metadata**. The raw report says complete
because its original gates passed, but this instrumented experiment must not be
used as ordinary no-forced-GC latency qualification or as a relative baseline.
The wrapper changed collection timing. No old failure was relabelled.

The [report](2026-10-27-native-retention-diagnostic-180.json) and
[native log](2026-10-27-native-retention-diagnostic-180.log) came from clean
`73f18bb` in the owned Ubuntu 24.04 container, two CPUs / 4 GiB, private Xvfb,
GTK/WGPU and Mesa llvmpipe Vulkan. The 72×22 workload used styled Unicode and
full-screen history scrolling, 40 measured inputs and six warmups over a
requested 180 seconds. Other Kiwi builds/tests/benchmarks were not concurrent;
unrelated workstation load and thermals were uncontrolled.

| Checkpoint | Heap before GC, KiB | Heap after GC, KiB | Collection seconds | History evictions |
| --- | ---: | ---: | ---: | ---: |
| Initial | 351,293.279 | 130,864.084 | 0.4750 | 70,763 |
| Final | 297,040.229 | 131,250.658 | 0.4100 | 682,371 |

Both checkpoints retained exactly 10,000 rows. Post-collection growth was
386.574 KiB across 611,608 additional history evictions. This is evidence of
bounded live Lua storage for this experiment, not proof that every workload or
native resource is leak-free. The raw allocated-heap medians grew 6,533.62 KiB,
while the earlier ordinary ten-minute run grew 54,633.08 KiB by the same sampled
statistic. Different GC phases, durations and runs prevent a causal comparison.

All 40 measured inputs completed (p95 179.10 ms, maximum 437.19 ms). Resource
observations span 188.41 seconds. RSS median growth was 40,756 KiB and sampled
peak RSS 681,844 KiB. These are diagnostic observations under endpoint collection,
not a substitute for the ordinary ten-minute workload.

## Reproducible benchmark mode

`script/bench-interactive --heap-measurement retained` now makes this measurement
explicit and records it in configuration, rather than relying on an invisible
external launcher. It is available only for sustained runs. It captures both
endpoints before teardown and with no outstanding timed input; full-history
endpoints must already hold the configured capacity. The 16 MiB growth gate
uses the independently recorded post-collection counts. Raw heap samples and
median growth remain visible. All other existing resource, duration, history,
visibility and response gates remain in force. The default sampled mode and its
no-forced-collection contract are unchanged. Relative comparisons require the
same recorded heap-measurement mode.

Regression tests distinguish real live allocations from temporary garbage;
verify checkpoint/history isolation and collection cost; reject invalid order,
incomplete history and failed collection; exercise both CLI modes and unchanged
RSS limits; and reject missing, inconsistent or non-finite retained evidence.
The latter exposed an existing parent-report bug: accepting non-finite JSON made
failure serialization fail. Child reports now reject non-finite numbers before
admission and enforce the existing 128 KiB child-report limit.

At implementation commit `58eb980`, Intel macOS `make check` passed 700 Lua
checks across 135 suites, 19 PTY integration tests and the supporting harness,
readiness, regex, terminfo, CLI and syntax checks. Bash/Zsh/fish/Nushell were
required. The three targeted retention/sustained/input-measurement suites also
passed all 16 tests with the JIT disabled. The final numeric-parser adjustment
was followed by another successful interactive-harness run.

## Explicit retained-mode ten-minute qualification

The [native 600-second report](2026-10-27-native-retained-heap-600.json) at clean
`34d4bed` used `--heap-measurement retained` directly, without the external
launcher, profiler or trace callbacks. The runner, GTK/WGPU, software Vulkan
adapter, grid, styled-Unicode traffic and 10,000-row history were otherwise the
same as above. No other Kiwi workload ran concurrently. Linux's three targeted
suites passed all 16 tests, and both interactive harness checks passed before
this trial.

All 120 measured inputs and six warmups completed. Retained checkpoints span
624.31 seconds excluding the initial collection, with 10,000 rows present at
both endpoints. History evicted 2,567,758 rows in total. Results:

| Gate/observation | Result | Limit |
| --- | ---: | ---: |
| Callback-to-present-return p95 | 231.01 ms | diagnostic |
| Maximum measured response | 263.21 ms | 2,000 ms |
| Live Lua heap, initial → final | 130,891.695 → 131,495.578 KiB | — |
| Retained Lua heap growth | 603.883 KiB (0.59 MiB) | 16 MiB |
| Sampled RSS median growth | 41,068 KiB (40.11 MiB) | 64 MiB |
| Sampled peak RSS | 685,148 KiB (669.09 MiB) | 1 GiB |
| Initial / final full collection | 291.98 / 354.34 ms | outside input timing |

Startup-ready presentation was 502.41 ms. The slowest input reached the PTY in
1.44 ms; pending work included 72.81 ms parsing, 119.26 ms preparation and
54.70 ms rendering. Process CPU averaged 168.27%. Post-exit JIT inspection found
905 traces and 1,665,381 emitted machine-code bytes.

The report is complete under its **explicit retained-mode contract**. The raw
allocated-heap quarter medians still grew 39,503.73 KiB (38.58 MiB), which would
fail the unchanged sampled-mode heap gate. That statistic remains in the report.
The earlier ordinary sampled failure is not relabelled. Together, the ordinary
run's completed latency samples and this live-retention measurement provide
stronger evidence than treating collection-phase medians as proof of a leak.
They do not establish repeatable timing, hardware-GPU behavior, physical input
latency or a speed advantage over another terminal. macOS long visible-window
qualification and a fixed-runner regression baseline remain separate work.
