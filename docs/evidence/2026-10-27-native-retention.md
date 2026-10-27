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
