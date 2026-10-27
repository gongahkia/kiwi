# Unicode cluster storage and native latency follow-up, 2026-10-27

## Ordinary native run with post-exit inspection

At clean `4c65f19`, the [requested 600-second GTK/WGPU run](2026-10-27-history-linux-gtk-postrun-jit-failure.json)
failed on sequence 31 after 24 measured inputs, with an unparsed acknowledgment
pending for 3,602.59 ms. The input reached the PTY after 3.52 ms. One 4 KiB read
then used 879.20 ms wall / 844.25 ms process CPU parsing and 2,282.49 ms wall /
2,127.54 ms CPU preparing the frame. Rendering used 79.78 ms wall / 100.69 ms
process CPU. Startup took 23.56 seconds; completed-input p95 was 1,794.90 ms.

The run used the owned two-CPU/4-GiB Ubuntu container, Xvfb, GTK and llvmpipe on
the shared Intel Mac. No other Kiwi tests ran concurrently. Host load and
thermals were uncontrolled. There were no profiler or JIT trace callbacks.
After application exit, the new diagnostic observed 799 retained traces, maximum
trace number 799, 98,805 IR instructions and 1,456,697 emitted machine-code bytes.
This is below the configured limits, but a final snapshot cannot prove that
there were no earlier flushes. Neither limit was increased.

Post-warmup observations cover only 148.20 seconds, not the requested 600.
History retained 10,000 rows after 55,230 evictions. Sampled peak RSS was
661,712 KiB; RSS quarter-median growth was 80,464 KiB and heap growth negative.
This is failed latency and incomplete soak evidence, not qualification.

## Bounded sharing of immutable cluster arrays

The existing ASCII path shares immutable codepoint arrays. Unicode previously
created an array for every new scalar and every grapheme extension, even when
identical text already occupied thousands of retained cells. `cluster_pool.lua`
extends the same immutable-array contract to Unicode using exact semantic UTF-8
keys. It retains at most 4,096 entries, with at most 256 key bytes and 64
codepoints per entry. FIFO eviction drops only the pool's reference. Longer
configured clusters bypass the pool without truncation or changed semantics.

Cells and their styles remain independent. Extending a cluster constructs or
finds a replacement array; it does not mutate the prefix. The shared pool is
outside state transactions, like the existing ASCII pool, so staged-state copies
do not duplicate a global cache or acquire mutable aliases. Dotted-circle display
substitutes are not semantic cache keys.

An isolated Intel macOS probe used an 80×24 terminal, 1,024 retained rows and a
line containing 32 `é` and 32 `é` clusters followed by CR/LF. After 50 warmup
lines and a collection, it wrote another 1,074 lines and collected again:

| Implementation | Retained Lua heap increase, KiB | Process CPU seconds, including final GC |
| --- | ---: | ---: |
| Previous state module | 17,424.33 | 0.419 |
| Bounded cluster pool | 11,941.48 | 0.258 |

These are single-process diagnostic observations, not a native responsiveness
or throughput baseline. The retained-memory regression allows 14 MiB and fails
against the previous state module at 17,425.29 KiB. The new tests also exercise
eviction without invalidating cell-owned arrays, entry/key bounds, uncached long
clusters, warmed allocation, separate terminals, history and transactional
grapheme extension. They pass with JIT disabled as well as targeted JIT-enabled
checks. Native sustained qualification remains required.

After the change, Intel macOS `make check` passed 690 deterministic Lua tests
across 133 suites, 19 PTY tests and the associated native, CLI, benchmark and
syntax checks. `make test-unicode` passed the pinned Unicode 17 extended-grapheme
conformance corpus and version check.

At clean `9895f15`, Linux passed 448 core tests across 75 suites with native
loading disabled, all [11 local application workflows](2026-10-27-cluster-pool-applications.json)
and all [six loopback SSH workflows](2026-10-27-cluster-pool-ssh.json). These
retain the existing combined editor/pager/tmux, resize, saved-file and replay
checks; they do not establish native latency.
