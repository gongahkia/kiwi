# Startup and acknowledged interaction baseline, 2026-10-26

Implementation: `56f5284`; startup-handshake/report corrections: `0372a39`.
CI and usage documentation: `e15eb9f`.

The new fixture follows a numbered acknowledgment from a synthetic text
callback through real input encoding, PTY delivery, a controlled child,
production parsing and successful WGPU compositor presentation return.
It verifies the complete matching acknowledgment in the visible model.
Only one input is outstanding, so unrelated traffic cannot satisfy a sample.
This is stronger association than the older pacing counter's first-later-output
heuristic, but does not measure physical keyboard, IME, GPU completion,
compositor feedback or panel scan-out.

Each host ran three fresh processes per mode, five excluded warmup inputs and
20 measured inputs per process: 60 measured inputs per mode. Requested window
size is 800×480 logical points, font size 18, scrollback limit 2,000, PTY read
budget 4 KiB and inter-input interval 20 ms. Layout restoration, extensions and
automatic configuration reload are disabled. Saturated ASCII output scrolls
below a reserved acknowledgment row and starts with the first warmup input.

## Recorded baseline

All reports identify `0372a39`: macOS records a clean worktree; Linux runs an
archive of that commit in the owned Ubuntu 24.04 x86_64 2-CPU/4-GiB container.
Linux uses Xvfb and software Vulkan. macOS uses its native Metal path on the
Intel host. Actual geometry was 72×24 cells at 22×41 pixels on macOS and 72×22
at 11×21 pixels on Linux. This is not a controlled platform comparison.

| Host | Idle launch → ready presentation, median | Idle callback → presentation, pooled p95 | Saturated callback → presentation, pooled p95 | Saturated maximum |
| --- | ---: | ---: | ---: | ---: |
| macOS GLFW / Metal | 835.6 ms | 9.4 ms | 84.1 ms | 84.3 ms |
| Linux GLFW / software Vulkan | 241.6 ms | 17.2 ms | 142.9 ms | 164.5 ms |
| Linux GTK / software Vulkan | 487.5 ms | 16.1 ms | 129.0 ms | 146.6 ms |

Raw reports retain all trial metadata and samples:
[macOS](2026-10-26-interactive-macos.json),
[Linux GLFW](2026-10-26-interactive-linux-glfw.json),
[Linux GTK](2026-10-26-interactive-linux-gtk.json).

Startup includes interpreter, native host/font/GPU setup and the fixed Python
child. Filesystem/driver caches were not flushed. Idle trials run before loaded
trials, so differences between their startup observations must not be attributed
to the output workload. Input samples within a process are correlated; these
small distributions do not establish statistical confidence or a speed advantage
over another terminal. No physical display-latency or cold-cache claim is made.

The phase split gives the next investigation a concrete target. Saturated
callback-to-completed-parse p95 was 69.3 ms on macOS, 128.9 ms on Linux GLFW and
116.5 ms on Linux GTK. Parse-to-presentation-return p95 was 16.7/20.4/20.6 ms.
Quantiles of separate phases do not sum to the total p95. These observations
suggest investigating child/PTY backlog and application read/render scheduling;
they do not by themselves identify a single cause or prove a fix.

## Correctness and failure handling

An early longer run timed out before completing saturated startup. The fixture
now waits for an observed ready presentation before the first warmup input
starts background traffic, and refreshes the child's scroll region from the
current PTY geometry. Three loaded macOS runs completed after that change,
followed by the full committed-source matrix above. This was a fixture
qualification issue, not evidence that a production stall was fixed.

The acknowledgment header precedes its visible text. Native reads may split
either; timing only accepts both after complete matching text is parsed. A
deterministic test feeds the protocol byte by byte and floods the separate
scroll region afterward. Additional tests cover stale/unrelated events,
duplicate observations, clock/order errors, warmup exclusion, bounded counts
and incomplete results. The CLI test deliberately fails the application and
checks that an old successful report is replaced with explicit failure.

Reports atomically transition through `running`, `failed` and `complete`,
preserving completed trials and a failure record on error. Only `complete`
reports qualify as baselines. Each acknowledgment, including warmup, has a
two-second ceiling; each trial has a 30-second internal and 40-second external
deadline. These are gross responsiveness/correctness gates, not a relative
performance budget or acceptable interactive-latency target.

Both platforms pass **658 full tests / 130 suites** and **418 core tests / 72
suites**; Linux also passes `make check`, including the new CLI test. The exact
short CI recipe (one process per mode, one warmup and four measured inputs)
passes locally on macOS and Linux GLFW/GTK WGPU. GitHub jobs are configured to
run it and retain reports/logs; hosted CI was not triggered in this session.
GTK GL is explicitly unsupported by this measurement fixture. Physical desktop
qualification, comparative regression budgets, further performance work and
distribution remain open.
