# Sustained native load qualification, 2026-10-26

These results concern the numbered PTY acknowledgment workload in
[the benchmark contract](../BENCHMARKS.md). They do not measure physical keyboard
delivery, GPU completion or display scan-out. Windows is deferred by the user.

## Intel macOS: incomplete visible-window qualification

Two retained clean-source trials used saturated styled-Unicode output, 120
measured inputs, six warmup inputs and a requested 600-second measurement.

- [Surface diagnostic](2026-10-26-soak-macos-surface.json), revision `b88699b`:
  104 measured inputs completed before the two-second response ceiling failed.
  The pending input had reached the model. Metal returned `surface occluded`
  23 times; the last successful presentation was 5.77 seconds earlier. The
  post-warmup resource series spans 529.12 seconds: RSS quarter-median growth
  2,592 KiB, peak 179,564 KiB. These are partial observations, not a soak pass.
- [Floating-window attempt](2026-10-26-soak-macos-floating.json), revision
  `0741987`: one measured input completed before an occluded surface invalidated
  the run. The GLFW floating attribute was set and verified. This option does
  not guarantee AppKit visibility throughout a run on a shared workstation.

The pinned wgpu-native `v29.0.1.1` Cargo lock selects wgpu-hal `29.0.3`.
Its Metal `acquire_texture` implementation checks `NSWindow.occlusionState`
before acquiring a drawable and returns `SurfaceError::Occluded` when the
visible bit is absent. `nextDrawable` returning nil produces `Timeout` instead.
Sources: [lockfile](https://github.com/gfx-rs/wgpu-native/blob/v29.0.1.1/Cargo.lock),
[Metal implementation](https://docs.rs/crate/wgpu-hal/29.0.3/source/src/metal/surface.rs).
This confirms the status distinction; it does not identify why the workstation
changed the window's visibility. No production GPU recovery changes or relaxed
latency thresholds were made. macOS long-duration visible qualification remains
open and needs an uninterrupted graphical session.

## Linux software Vulkan: bounded sustained runs passed

Both trials ran sequentially in Ubuntu 24.04 x86_64, using Xvfb and the actual
llvmpipe Vulkan adapter in the owned container (two CPUs, 4 GiB memory limit).
No application-test/build workload ran concurrently with either measurement.
The shared host was not a controlled thermal/performance laboratory.

| Host | Measured inputs | Post-warmup duration | RSS growth | Peak RSS | Input p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| GLFW | 120 | 642.62 s | 4,992 KiB | 199,716 KiB | 520.91 ms |
| GTK WGPU | 20 | 73.03 s | 162 KiB | 284,592 KiB | 646.26 ms |

[GLFW report](2026-10-26-soak-linux-glfw.json),
[GTK report](2026-10-26-soak-linux-gtk.json). Both completed every acknowledgment
within two seconds and passed the default RSS/heap-growth/peak budgets. Lua heap
quarter-median growth was negative in both. GLFW process CPU averaged 153.7%
across cores; software rasterization under sustained load is not an idle-power
measurement. These relatively high response times are not competitive GPU
latency evidence, and these different-duration/host trials are not a relative
performance comparison.

GLFW used source archive `9b2f126`; GTK used `a82c51f`. The reports identify the
archive revision from `BUILD_REVISION` and do not attest Git cleanliness. The
strict relative-budget checker correctly requires stronger clean-source evidence.
This qualifies one bounded scrolling-region workload, not full scrollback,
hour-long sessions, hardware GPU drivers, physical display latency or all memory
retention patterns. The longer macOS gate remains incomplete as described above.
