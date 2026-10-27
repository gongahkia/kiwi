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

## Follow-up after compact Unicode storage

A [60-second GLFW probe](2026-10-27-history-linux-glfw-10000-compact.json) at clean
revision `2ab1fed` completed all 20 inputs but failed the unchanged memory-growth
gate. Its post-warmup duration was 72.28 seconds, with 36,346 pushes, 26,346
evictions and exactly 10,000 retained rows. Peak RSS was 905,304 KiB; RSS
quarter-median growth was 350,622 KiB and heap growth 177,707 KiB. This shorter
probe does not establish an input-latency improvement over the interrupted
ten-minute run. It confirms that removing redundant Unicode cell storage is
insufficient to qualify large-history native load. Further investigation must
distinguish retained cell cost, transient allocations and collection timing.

## Follow-up after packing retained history cells

Revision `46da986` packs history cell values into arrays while leaving active
screen cells as ordinary tables. Reflow expands copied cells before placing them
on the screen; staged configuration copies preserve the representation and keep
mutable cell objects separate. Palette resolution can still update named fields.
A new styled-history memory test fails against `933d8c7` and passes after packing.
Both representations are tested for style removal, Unicode clusters and copy
isolation. `make check` passed 668 Lua tests across 131 suites and its integration
checks. All [11 real local application cases](2026-10-27-packed-history-applications.json)
and [six SSH cases](2026-10-27-packed-history-ssh.json) passed at clean `46da986`.

An [exploratory model comparison](2026-10-27-packed-history-model.json) used
three alternating baseline/candidate processes on Intel macOS. Median retained
Lua heap fell from 252,221 to 142,326 KiB (43.6%); median sampled peak fell from
563,704 to 396,653 KiB. Median CPU time was 4.71 versus 4.48 seconds. This is not
a native latency qualification or an approved performance baseline. The first
baseline process briefly overlapped the tail of a small cell-test process;
workstation load was otherwise uncontrolled. The candidate was uncommitted at
measurement time, as recorded in the JSON. The [probe source](2026-10-27-history-storage-probe.lua)
can be run with `LUA_PATH='src/?.lua;src/?/init.lua;;' luajit docs/evidence/2026-10-27-history-storage-probe.lua`.
The baseline comparison prepended copies of `cell.lua`, `state.lua`,
`state_transaction.lua` and `reflow.lua` from `933d8c7` to the module path.

Two native GLFW runs used clean `46da986`, the same 10,000-row capacity,
requested 60 seconds, 20 measured inputs, six warmup inputs and unchanged gates:

| Run | Measured inputs | History pushes / evictions | Peak RSS | Result |
| --- | ---: | ---: | ---: | --- |
| [Initial attempt](2026-10-27-history-linux-glfw-10000-packed-warmup-failure.json) | 0/20 | 709 / 0 | 195,016 KiB | Response ceiling exceeded during warmup |
| [Repeat](2026-10-27-history-linux-glfw-10000-packed.json) | 20/20 | 20,944 / 10,944 | 571,460 KiB | Memory-growth gate failed |

The initial run also took 4.14 seconds to reach child readiness. After it exited,
the workstation reported load averages of 29.05, 21.50 and 36.43. This suggests
contention as a possible contributor, but does not establish the failure's cause.
The failed report is retained. The repeat ran after application regression checks
finished, with no concurrent Kiwi build/test. Its observed post-warmup duration
was 77.57 seconds and input p95 1006.36 ms. It retained exactly 10,000 rows after
more than a full replacement. RSS quarter-median growth was 227,090 KiB and heap
growth 139,645 KiB, both above the existing limits. Peak RSS was lower than the
previous 905,304 KiB run, but differing load and throughput prevent treating this
as a controlled native speed comparison. Large-history qualification remains
incomplete. Subsequent fixture instrumentation records retained rows, pushes and
evictions at resource-sample times to distinguish initial filling from growth
after saturation; it does not alter the memory gates or force garbage collection.
