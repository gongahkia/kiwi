# macOS benchmark clock qualification, 2026-10-27

The first Intel macOS 600-second visible-window attempt at clean `e15b8a1`
used the explicit retained-heap mode, styled Unicode, 10,000 history rows,
120 requested inputs and six warmups. The [raw failure report](2026-10-27-macos-history-clock-failure.json)
records thirteen completed measured inputs before `Interactive:present` rejected
an observation older than the previous presentation timestamp. The original
failure did not retain the precise negative delta, so its magnitude is unknown.

Resource observations span only 64.81 post-warmup seconds. The initial live
retained-heap checkpoint completed, but there is no final checkpoint. These are
partial observations and do not qualify macOS sustained latency or memory.
One surface-occlusion event occurred before readiness; the reported terminating
failure was the backwards presentation clock, not that startup event. Previously
completed input maximum was 116.76 ms. No timestamp was clamped or accepted.

## Clock-source investigation

The native metric helper and parent launcher both used `CLOCK_MONOTONIC`.
[Apple's published implementation](https://github.com/apple-oss-distributions/Libc/blob/main/gen/clock_gettime.c)
computes that clock through calendar/boot-time values at microsecond resolution.
Its `CLOCK_MONOTONIC_RAW` instead uses `mach_continuous_time` with the platform
timebase, including time spent asleep and without calendar adjustment.

A separate [45-second C probe](2026-10-27-macos-clock-probe.c), compiled with
`cc -std=c17 -O2 -Wall -Wextra -Werror`, compared consecutive integer nanosecond
readings from both clocks. Across 410,205,244 pairs it found **no backwards steps
in either clock**; see the [output](2026-10-27-macos-clock-probe.log). Thus the
specific native failure's root cause is not established by that probe. The
source distinction motivates using the unadjusted continuous domain, but does
not prove a wall-clock adjustment caused the observed failure.

The native benchmark metric helper now uses `CLOCK_MONOTONIC_RAW` on macOS and
keeps `CLOCK_MONOTONIC` on Linux. Its clock name is exposed alongside the reading.
The parent uses the same selected domain and passes its name to the child, which
rejects a mismatch. Interactive configuration records the clock so historical
reports cannot silently form a mixed-domain comparison. The PTY burst benchmark
also uses this shared native helper instead of maintaining its own platform
clock IDs and allocating a timespec on each read. Application event-loop clocks
and collector settings are unchanged.

Presentation ordering remains strict. A subsequent backwards timestamp will
preserve the negative delta and include 17-digit observed/reference timestamps
in the error, rather than losing the discrepancy through JSON rounding. Native
metrics tests bracket 10,000 consecutive helper reads in the declared clock
domain. Parent/child fixtures check clock identity and launch-time ordering;
comparison fixtures reject different recorded clocks. Native endurance follow-up
is still required before claiming this addressed the macOS qualification failure.
