# GTK GL configuration qualification, 2026-10-26

Implementation commits: `574c5e6` (shared runtime and page transaction),
`79eb5b8` (native fixture/CI), `0cd2ca4` (equivalent-save fast path),
`acef443` (hidden-page scale regression).
`9dab072` fixes native atlas replacement when successive fonts use equal cache
generations.

`script/gtk-configuration-reload-smoke` passes on Ubuntu 24.04 x86_64 with
GTK 4.14, Xvfb and software GL in the owned 2-CPU/4-GiB qualification container.
It runs once with one page and once with two independent native tabs. The
Python wrapper provides a 35-second external watchdog for each run; the Lua
driver has a 25-second stage deadline. Its explicit 10 ms inspection tick is
test scaffolding, not the production application's idle policy.

Each run verifies:

- A comment-only atomic save changes no prepared resources.
- Invalid source retains the current configuration and records a title error.
- Automatic reload changes fonts/palettes while retaining state identity and
  more than 100 lines of scrollback per page.
- A failure constructing the last page's replacement consumer rolls back every
  page; a subsequent valid save recovers.
- Automatic-reload opt-out ignores a save until the default F6 binding is used.
- The original children accept distinct input and return matching output after
  all replacements; no replacement child is spawned.
- Every page's native framebuffer contains more than 100 pixels matching the
  final `#abcdef` background, including the tab hidden during earlier reloads.

Deterministic tests additionally inject font/consumer construction failures at
each of four points across two pages, check exact disposal counts and retention
of original resources, preserve hidden-page geometry, and exercise debounce,
missing-file dependencies, watcher failure and manual retry.

Linux `make check test-core gtk-host-check`, GTK GL lifecycle and colour-glyph
readback pass. PRIMARY regressions pass on both GTK GL routes. Final counts are
647 full tests / 127 suites and 407 core tests / 69 suites on both hosts. macOS runs the same
deterministic transaction/runtime tests; it does not run the Linux GTK fixture.

Final ownership review found a native texture-cache defect: a new font atlas
with the same size/generation could leave old glyph pixels displayed. A red-to-
blue atlas replacement fixture failed on the old code and passed after the
explicit update invalidated the upload cache. Both configuration routes passed
again after the fix. This glyph readback is distinct from the palette assertions.
The [expected pre-fix failure](2026-10-26-gtk-atlas-before.txt) and
[post-fix pass](2026-10-26-gtk-atlas-after.txt) are retained.

This qualifies the Xvfb test routes. It does not establish Wayland or physical
desktop behavior, large-history reload latency/memory, GTK custom shaders or
opacity, or preallocation of future GL driver resources. Existing performance
and desktop qualification gates remain open. See
[ADR 0046](../adr/0046-gtk-configuration-transactions.md).
