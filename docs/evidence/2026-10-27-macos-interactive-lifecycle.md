# macOS interactive qualification follow-up, 2026-10-27

The macOS ten-minute native qualification remains incomplete. Follow-up runs
separated early child termination, external input and startup surface occlusion.
They do not establish a fix for the earlier backwards-clock observation or a
passing endurance result.

## Observed failures

- At clean `d4607f5`, the [raw-clock endurance attempt](2026-10-27-macos-early-close.json)
  exited before any successful presentation or measured input. Its host log said
  `interactive benchmark closed before completion`; the old JSON omitted that
  reason. It recorded 57 PTY bytes and one startup surface-occlusion event. The
  report did not capture why the window closed.
- At clean `637c58b`, a [short native reproduction](2026-10-27-macos-child-exit.json)
  captured a child exit with code 1 and EOF **before** cleanup. The controller then
  requested close at its normal child-exit branch. No input samples completed.
  Thus this particular close was not merely a cleanup signal or unexplained
  native close flag.
- A subsequent diagnostic run with an uncommitted stderr-log change captured
  `AssertionError: benchmark requires exactly one outstanding input` in the
  Python protocol child. That run is diagnostic, not a clean timing baseline.
  It does not identify the contents or origin of the earlier run's input.
- At clean `a5b85f7`, the [input guard](2026-10-27-macos-external-input.json)
  invalidated the run on an external key callback, before the first presentation.
  No key contents are recorded. This directly demonstrates desktop input
  interference in that run, without inferring it from child exit alone.
- At clean `520894b`, the [unfocused-window trial](2026-10-27-macos-startup-occlusion.json)
  reached the child's readiness text but never presented successfully: all 118
  attempts returned `surface occluded` before the 30-second startup deadline.
  The child remained alive until cleanup. No external-input event was recorded.
  A separate read-only session query reported an on-console session, no reported
  screen lock and two active displays; it does not establish window visibility.
  Startup occlusion was also observed before the focus change, so this evidence
  does not establish that the focus hint caused it.

## Changes and regression coverage

`637c58b` preserves incomplete-return failures in JSON, first close-request stacks,
first observed close flags, and child state before/after shutdown. The new
`make test-interactive-trial` uses the real trial entry point and actual PTY
children with a controlled headless host. It checks explicit/native close, child
exit, exceptions, occlusion and completion, including hook restoration and reaping.
It does not replace native desktop qualification.

`6194c2b` writes protocol-child exceptions to a separate companion log, outside
the nonblocking PTY stream. A startup-error fixture verifies retained stderr.
Unexpected input diagnostics report byte counts, not typed contents.

`a5b85f7` invalidates external text, key, pointer, preedit and commit events before
they can affect an acknowledgment. Errors are raised after native event dispatch,
not through a native callback. A typed `x` is explicitly covered: it cannot impersonate
an instrumented input. Empty composition resets and pointer movement are harmless.

`520894b` requests GLFW benchmark window creation without keyboard focus. The
normal application default remains focused. The request is recorded in trial
configuration and is subject to the window manager; input guards remain enabled.

All eleven controlled trial scenarios pass on Intel macOS. The interactive CLI,
real protocol-child PTY tests and relative-budget/provenance checks also pass.
Seventeen deterministic timing/sustained/retained-heap tests passed during the
lifecycle change. No native latency or memory threshold was relaxed, and no
failed or invalid run was admitted as a passing baseline.

The same controlled trial, CLI/real-child and regression-budget checks pass in the
isolated Ubuntu container. At clean `520894b`, [GTK/WGPU native smoke trials](2026-10-27-lifecycle-linux-gtk.json)
also passed on Xvfb with Vulkan llvmpipe: four measured inputs plus one warmup
under each of idle and saturated styled-Unicode output. Callback-to-present p95
was 38.83 ms idle and 290.15 ms saturated. Both children were alive before normal
completion cleanup and reaped afterwards. These short runs verify instrumentation
integration; they are neither endurance evidence nor a comparative speed claim.

[GLFW/WGPU smoke trials](2026-10-27-lifecycle-linux-glfw.json) at the same clean
revision also passed both workloads on isolated Xvfb/llvmpipe with the new
no-focus creation request. Four measured inputs per mode gave p95 27.39 ms idle
and 425.36 ms saturated; both PTYs closed and children were reaped. The small
samples and shared software-rendering host do not justify ranking the hosts.
