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
