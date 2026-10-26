# Event-wait qualification, 2026-10-26

Scope: Linux/macOS live scheduling. Windows is deferred. This increment removes
the blanket application timer; it does not complete desktop, performance or
distribution qualification. Architecture and fallback conditions are in
[ADR 0045](../adr/0045-event-driven-host-waits.md).

Implementation: `39838f3`/`828aab3` (GLib readiness), `c31bd0f` (child exit),
`768f7f2` (application deadlines), `9539a37` (indefinite waits, power accounting,
callback boundaries). `7e25c44`/`653353e` add the quiet-window gate. Test-driver
fixes `c8e0a8d`/`42dbd62` remove their dependence on production polling.

## Functional evidence

Both hosts pass 639 deterministic tests across 125 suites and 400 native-free
core tests across 67 suites. `make check` passed at the scheduler increment;
the later changes add measurement/test-driver coverage. Native child tests
cover closed streams, exit status, 100 rapid exits, close-on-exec and descriptor
cleanup. PTY tests cover buffered writes, one-shot delivery and teardown.
Final child/PTY fixtures pass ASan/UBSan on both hosts; the GLib fixture also
passes ASan/UBSan on Linux. Syntax checks pass for all 359 Lua files.

`script/pty-wake-smoke` runs finite and indefinite waits with an external
20-second watchdog. Selected indefinite-wait observations:

| Host | Delayed output | 256 KiB buffered input | Exit after terminal EOF |
| --- | ---: | ---: | ---: |
| macOS GLFW | 71.0 ms | 265.9 ms | 251.9 ms |
| Linux GLFW/Xvfb | 54.8 ms | 210.5 ms | 215.6 ms |
| Linux GTK/Xvfb | 57.7 ms | 210.1 ms | 219.0 ms |

Children intentionally delay output by 50 ms, or reading/exit by 200 ms.
These values test readiness, not displayed input latency. Linux uses Ubuntu
24.04 x86_64 in a 2-CPU/4-GiB container, GLFW 3.4 and software graphics; macOS
uses an Intel i5-8279U with Metal. GTK's Xvfb EGL/DRI3 diagnostics remain visible
in logs and do not establish accelerated desktop qualification.

The private Linux AT-SPI fixture serves five actual text queries without
provider polling, maximum 13.4 ms with a two-second host wait. Configuration
reload passes on both hosts. Linux search, vi, selection rendering and URL hint
fixtures pass; PRIMARY passes GLFW/WGPU, GTK/WGPU, GTK GL and GTK GL native tabs.
GTK GL's two-second application deadline terminates a sleeping child on both
tab paths (2.43 s including startup/cleanup). A three-second macOS device soak
also completes resize/minimize/restore with an animated extension.

## Quiet-window observations and limits

`script/idle-wake-smoke` starts a quiet three-second child interval only after a
synthetic-input handshake, hides the cursor, and uses a private fixed-theme
configuration with automatic reload disabled. It requires an indefinite wait,
allows at most 30 host-loop wakes, and has an external watchdog. These are
controlled application observations, not OS wake attribution or energy data.

| Run | Host-loop wakes | Indefinite waits | Recorded seconds |
| --- | ---: | ---: | ---: |
| macOS baseline `c31bd0f` | 58 | 0 | 3.010 |
| macOS candidate, repeat 1 | 5 | 1 | 3.044 |
| macOS candidate, repeat 2 | 5 | 1 | 3.076 |
| macOS candidate, repeat 3 | 5 | 1 | 3.061 |
| Linux GLFW candidate | 4 | 1 | 2.876 |
| Linux GTK candidate | 5 | 1 | 2.917 |
| Earlier macOS candidate outlier | 87 | 82 | 2.935 |

The baseline was built from its own detached checkout/native sources. Its
duration measures intervals between observations; candidate durations measure
time inside native waits and exclude rendering/parsing CPU time. Do not compare
those durations as latency or throughput. Linux has no matched baseline here.
Three clean macOS candidate runs use `7e25c44`; Linux report revisions are
embedded in their JSON. The earlier outlier uses `9539a37` with the new fixture
uncommitted. Its excess wakeups are **unexplained**, so no universal reduction
or statistical speed/power claim is made. Three diagnostic runs and three clean
reruns subsequently passed; the outlier is retained, not discarded.

An initial mixed-source/native baseline attempt also hit LuaJIT's `bad callback`
panic. Rebuilding the baseline's own native library passed. Event-pump functions
now explicitly disable JIT compilation according to LuaJIT's callback contract;
the exact trigger of that first panic was not independently reproduced.

The first GTK quiet gate incorrectly required 2.8 seconds *inside native waits*;
its 2.783-second result excluded software-rendering CPU time. The corrected
fixture verifies the child's wall-clock interval separately. It retains the
wakeup budget and indefinite-wait assertion.

Raw reports:

- [macOS baseline](2026-10-26-idle-macos-baseline.json)
- [macOS repeat 1](2026-10-26-idle-macos-1.json), [repeat 2](2026-10-26-idle-macos-2.json), [repeat 3](2026-10-26-idle-macos-3.json)
- [macOS outlier](2026-10-26-idle-macos-outlier.json)
- [Linux GLFW](2026-10-26-idle-linux-glfw.json), [Linux GTK](2026-10-26-idle-linux-gtk.json)

Actual desktop screen readers, IMEs, monitor/suspend behavior, energy, displayed
latency and sustained resource budgets remain separate qualification gates.
