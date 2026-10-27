# Real-PTY burst qualification, 2026-10-27

At clean `599b4b1`, all five real-PTY burst cases passed on
[Intel macOS](2026-10-27-burst-after-allocation-macos.json) and the owned
[Ubuntu 24.04 container](2026-10-27-burst-after-allocation-linux.json).
The runs were sequential, without another Kiwi benchmark or build. Shared-host
load and thermals remained uncontrolled; these are absolute-gate results, not
a controlled comparison against earlier revisions or other terminals.

| Workload | macOS maximum service turn, ms | Linux maximum service turn, ms |
| --- | ---: | ---: |
| Printable 1 MiB | 14.165 | 84.535 |
| Mixed ANSI 1 MiB | 16.692 | 54.790 |
| Combining/CJK/emoji/PUA 128 KiB | 12.195 | 22.861 |
| Interleaved DSR response | 8.804 | 14.807 |
| Printable 10 MiB | 13.127 | 26.907 |

Both runs used the unchanged 250 ms maximum-turn and 64 MiB retained-Lua-heap
growth gates, 16 KiB turn ceiling, 4 KiB chunks and 8 ms cooperative target.
All children exited successfully, PTYs closed, expected byte counts arrived and
the reference-backed cases matched canonical snapshots. The DSR case wrote its
six-byte response while output was active. The reports retain actual heap/RSS
observations and full distributions; unavailable macOS RSS deltas are omitted.

This corpus retains 256 history rows and excludes text shaping, GPU submission
and native presentation. It therefore closes the current headless burst gate,
but **does not resolve** the [native full-history latency failures](2026-10-27-unicode-cluster-pool.md).
The allocation changes and revised protected harness both precede this run;
these observations cannot isolate the effect of either change.

## Failure reporting and cleanup

The previous burst script asserted before writing JSON on a failed latency or
memory gate. It could also leave its child alive after a parser error or deadline.
The revised harness protects the service loop, performs bounded PTY shutdown,
retains available measurements and writes an atomic `failed` report before the
CLI exits unsuccessfully. Earlier completed cases survive; later cases do not
run. Setup, cleanup and snapshot failures remain distinguishable. Reports begin
as `running`, replacing stale successes, and become `complete` only after all
requested cases pass.

`script/test-burst-bench` passed on macOS and Linux. Its ten real-PTY scenarios
cover success, service/heap rejection, nonzero child exit, truncated output,
snapshot mismatch, missing response, timeout, parser error and setup error. It
checks process exit, retained counters, previous results, discarded stale
reports, atomic replacement and that launched child PIDs no longer exist.
The fixture is included in `make check`; the full macOS check also passed all
690 deterministic Lua tests, 19 PTY tests and its associated native/CLI checks.
This is local evidence, not a claim of a hosted CI run.
