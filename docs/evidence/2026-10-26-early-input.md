# Deliver input before consuming output

`590ac8c` flushes queued keyboard/paste input before reading and parsing child
output in WGPU and both GTK GL controllers. Responses generated during parsing
still flush afterwards through the same FIFO. The ordinary read budget remains
4 KiB. An exploratory 64 KiB run did not improve the Mac ASCII acknowledgment
result enough to justify increasing that budget or introducing a new scheduler.

`606aa2f` also fixes an exit edge case: a PTY write returning EIO clears pending
input but does not set read EOF. Unread final output must still be drained.
The regression uses a real PTY with unread output and injects EIO into write
only; it fails against the previous handler (`expected false, got true`). A
controller regression checks same-turn acknowledgment parsing and FIFO ordering
of previously queued input followed by generated responses.

## Fixture corrections

`56bd234` adds explicit read-budget and ASCII/styled-Unicode controls. The latter
includes RGB, bold, italic, underlining, combining marks and wide characters.
The child now handles SIGWINCH through a wakeup pipe and repaints readiness
before the first input. A control run exposed readiness text displaced by
initial native allocation; that failed report is not a usable baseline.
Native-free Python checks exercise actual PTY startup/resize and both workloads.

`d7e1b8c` corrects the load sanity check. Requiring 4 KiB consumed per input
rejected faster acknowledgments despite continuous output. It now reserves
256 bytes per acknowledgment for protocol overhead and requires an additional
4 KiB of background traffic over the trial. The child continues producing output
whenever the PTY is writable after the first warmup input. The two-second acknowledgment ceiling,
one-outstanding-sequence association and external watchdog remain unchanged.

## Sequential comparison

Before is **d7e1b8c**; after is **606aa2f**. Mac reports come from clean source
worktrees sharing the same native libraries. Linux uses source archives and a
recorded BUILD_REVISION. Each workload has three fresh processes, five warmup
inputs and twenty measured inputs per process. All use a 4 KiB read budget and
20 ms inter-input interval. These are pooled percentiles of correlated samples,
not sixty independent process observations or statistical confidence intervals.

The comparisons below ran sequentially, with no other Kiwi benchmark running.
The Linux container was stopped during the final Mac comparison. Earlier runs
that overlapped Mac and container workloads are excluded. This is still a
shared workstation: unrelated work, thermal state and scheduling were not
controlled. The substantial variation in Linux trials limits conclusions.

| Host / loaded traffic | Before p95 | After p95 | Before maximum | After maximum |
| --- | ---: | ---: | ---: | ---: |
| macOS Metal / ASCII | 84.8 ms | 34.4 ms | 94.9 ms | 35.0 ms |
| macOS Metal / styled Unicode | 84.6 ms | 68.2 ms | 85.1 ms | 90.6 ms |
| Linux GLFW WGPU / ASCII | 254.5 ms | 241.3 ms | 270.1 ms | 354.9 ms |
| Linux GTK WGPU / ASCII | 215.1 ms | 143.1 ms | 253.6 ms | 161.9 ms |

The Mac ASCII result improves consistently across these three trials. The Mac
Unicode p95 improves, but its maximum worsens. Linux GLFW provides no convincing
improvement: per-trial p95 spans 206.8–269.1 ms before and 167.1–268.2 ms after,
and the maximum worsens. GTK's p95 is lower in this run; this does not establish
a general Linux performance guarantee. Phase quantiles are recorded separately
and must not be added together.

Candidate-only Linux styled-Unicode p95 is 462.8 ms for GLFW and 465.3 ms for GTK;
the maximum is 482.5 and 548.9 ms respectively. These pass the coarse two-second
ceiling but show substantial remaining cost. There is no matching Linux Unicode
baseline in this increment, so no improvement is claimed for that workload.

Mac uses Intel Iris Plus / Metal, 72×24 cells with 22×41 pixel cell metrics.
Linux uses a 2-CPU, 4-GiB Ubuntu 24.04 container, Xvfb and software Vulkan, with
72×22 cells at 11×21 pixels. Do not compare absolute speeds across those hosts.
Measurements end at CPU return from successful WGPU presentation; physical
keyboard delivery, GPU completion, compositor feedback and scan-out are excluded.

## Verification and remaining work

Both hosts pass `make check`: **659 Lua tests across 130 suites**, **18 PTY
integration tests**, fuzz, readiness, CLI, benchmark-fixture and syntax checks.
Native finite/indefinite waits still service output, 256 KiB backpressured input
and child exit. GTK GL single-page and native-tab configuration checks pass.
Quiet-window gates pass with five Mac wakes, four Linux GLFW wakes and five
Linux GTK wakes, each entering an indefinite wait.

Short ASCII and styled-Unicode native CI recipes pass locally on Mac x86_64 and
both Linux WGPU hosts. The workflows now include styled Unicode; hosted CI and
Mac ARM64 execution have not been performed here. This increment does not close
the broader performance, physical desktop or distribution qualification gates.

## Raw reports

- macOS ASCII: [before](2026-10-26-early-input-macos-before.json), [after](2026-10-26-early-input-macos-after.json).
- macOS styled Unicode: [before](2026-10-26-early-input-macos-unicode-before.json), [after](2026-10-26-early-input-macos-unicode-after.json).
- Linux GLFW ASCII: [before](2026-10-26-early-input-linux-glfw-before.json), [after](2026-10-26-early-input-linux-glfw-after.json).
- Linux GTK ASCII: [before](2026-10-26-early-input-linux-gtk-before.json), [after](2026-10-26-early-input-linux-gtk-after.json).
- Linux candidate styled Unicode: [GLFW](2026-10-26-early-input-linux-glfw-unicode.json), [GTK](2026-10-26-early-input-linux-gtk-unicode.json).

Reproduce each revision with `script/bench-interactive --report PATH`, followed
by `--mode saturated --traffic styled-unicode --report PATH`. Linux additionally
needs `xvfb-run -a`, the appropriate Vulkan ICD and optionally `KIWI_HOST=gtk`.
