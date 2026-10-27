# Full-history native load qualification, recorded 2026-10-27

These retained runs were measured on 2026-10-26 at clean Git revision
`c4adb2be1c43191205db7b45d5265a529dfddf27`, before the subsequent Unicode storage
and repaint fixes. Both used the owned Ubuntu 24.04 container, two CPUs, 4 GiB
memory limit, Xvfb and Mesa llvmpipe Vulkan. They exercise the production parser,
scrollback and presenter with saturated styled-Unicode output. They measure
synthetic input callback to visible acknowledgment and successful present return,
not physical keyboard delivery or scan-out. No build or application test ran
concurrently, but the shared workstation's load and thermals were uncontrolled.

Unlike the earlier scrolling-region soak, this workload scrolls the entire
primary screen. Instrumentation counts actual history pushes and evictions and
checks the capacity throughout the run. The PTY child repaints its acknowledgment
between output lines so it remains observable across parser read boundaries.

| Run | Measured inputs | Observed post-warmup duration | History capacity | History pushes / evictions | Peak RSS | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| [GTK, requested 60 seconds](2026-10-27-history-linux-gtk-2000.json) | 20/20 | 69.21 s | 2,000 | 45,283 / 43,283 | 434,676 KiB | Passed |
| [GLFW, requested 600 seconds](2026-10-27-history-linux-glfw-10000.json) | 8/120 | 53.29 s | 10,000 | 30,495 / 20,495 | 912,152 KiB | Failed |

GTK retained exactly 2,000 rows after more than twenty complete replacements.
Input p95 was 372.66 ms. RSS quarter-median growth was 140 KiB; Lua heap growth
was negative. This passes the existing absolute response and memory gates for
this one workload and duration. It does not qualify larger histories or hardware
GPU latency.

The GLFW run retained exactly 10,000 rows and evicted more than another 20,000,
but failed the two-second response ceiling. Pending sequence 15 had not reached
the observed model acknowledgment after 2.38 seconds. Presentation remained
available: 902 successful presents, no failed presents, and the last successful
present only 0.84 ms earlier. This differs from the previously recorded macOS
occlusion failure. The report alone does not establish the cause of the delayed
acknowledgment.

The incomplete GLFW series reports RSS quarter-median growth of 164,056 KiB and
Lua heap growth of 126,274 KiB, both beyond the normal completed-soak budgets.
Its small three-sample quarter windows cover initial retention and garbage
collection cycles; these values do not establish an unbounded leak. Nevertheless,
roughly 891 MiB peak RSS is a substantial cost, and this is not a qualified
ten-minute run. No budget was relaxed. Further memory reduction and renewed
native load qualification remain open.
