# Terminal parity implementation

Scope: the seven workstreams requested on 2026-10-25, plus the distribution
work from the preceding assessment. This ledger records implementation and
verification separately. An unchecked item is still required; local macOS
tests do not establish Linux or Windows desktop qualification.

**User scope update — 2026-10-26:** finish and verify the remaining non-Windows
work first, then stop this task and provide a Windows handoff. The user will
continue Windows work on their Windows laptop. Do not implement Windows during
this task; its unchecked items below are deferred and are not completion gates
for the current non-Windows scope. All other unchecked work remains in scope.

## Text rendering

- [x] Recover bounded glyph storage after saturation without corrupting cached
      rows, other panes, or retained GPU frames; exercise repeated churn.
- [x] Resolve real bold/italic faces, with an explicit synthesis policy.
- [x] Render underline variants and colours, including blank cells.
- [x] Improve fallback consistency and render bitmap colour emoji; COLRv1/SVG
      remain outside the implemented font-format subset.
- [x] Add deterministic layout/bitmap/readback regressions and stress evidence.

## Common applications

- [x] Reproduce and close the recorded tmux protocol qualification failures.
- [ ] Exercise real tmux, Neovim, Vim, shells, SSH, pagers, and full-screen
      monitoring tools, including resize, alternate screens, queries and input.
- [x] Automate local PTY workflows for Bash/Zsh, Vim/Neovim, tmux, nested Neovim,
      less and system top, with saved-file assertions and replay verification.
- [x] Exercise real authenticated loopback SSH with remote shell/editing,
      tmux/resize, saved-file assertions and disconnect/HUP cleanup.
- [x] Preserve reproducible captures and configure regression gates in CI.

## Desktop reliability

- [ ] Qualify clipboard and primary selection on X11 and Wayland.
- [ ] Qualify IME composition and accessibility with native consumers.
- [ ] Exercise fractional DPI, monitor transitions, suspend/resume and recovery.
- [ ] Resolve differences between Linux presentation paths; document and test
      the supported application path without claiming prototype equivalence.

## Windows — deferred to the user's Windows laptop

- [ ] ConPTY creation, resize, I/O, cancellation and child lifecycle.
- [ ] Window/GPU integration, input, fonts, clipboard, IME and accessibility.
- [ ] Build, packaging and Windows CI with actual application execution.

## Performance and power

- [ ] Measure startup, input latency, throughput, memory and idle wakeups.
- [x] Remove the blanket application timer while preserving output, buffered
      input and child-exit readiness; retain explicit unsupported-platform fallbacks.
- [ ] Run representative load/soak workloads with bounded resource assertions.
- [ ] Record reproducible baselines and regression thresholds; distinguish CPU
      microbenchmarks from displayed latency and same-machine comparisons.

## Configuration

- [x] Stage and atomically commit font/renderer/configuration replacement on the
      supported WGPU application path; GTK GL prototype parity remains open.
- [x] Debounce automatic file reload and show recoverable configuration errors
      on WGPU; Linux graphical execution and GTK GL parity remain open.
- [x] Inject resource failures and verify the old session remains usable.

## Search and keyboard navigation

- [x] Bounded regex search with cancellation and Unicode-aware results.
- [x] Bounded vi-style navigation and character/line/word/rectangular selection.
- [x] Keyboard URL hints with bounded discovery, explicit preview/open/copy and native regression gates.
- [x] X11 pointer-primary selection with explicit ownership and clipboard policy.
- [x] Extend primary selection to keyboard copy/paste, Find paste and completed vi publication.
- [ ] Qualify primary selection on actual desktops.

## Distribution

- [ ] Reproducible Linux/macOS/Windows packages and clean-machine installation.
- [ ] macOS signing/notarization support and full release qualification.
- [ ] Record external credentials, hardware and qualification requirements
      explicitly; do not count unavailable validation as a passing gate.

## Evidence

Baseline worktree: `afbd89c`, clean. Read the complete supplied requirements
before implementation. Changes are committed as independently reviewable units.

### Bounded glyph-cache recovery

The cache reclaims least-recently-used unpinned glyphs, preserves live UVs with
a coalescing allocator, and pins unchanged rows and other panes. Capacity
failures are retried after owners release space. Oversized allocations are
rejected without consuming or evicting usable storage. The page and entry
budgets remain fixed; an oversized simultaneous visible working set can still
produce a temporary fallback.

`make check` passed after the change, including full Lua, PTY, readiness,
terminfo, CLI, fuzz and syntax gates. A 5,000-round mixed-text stress run plus
5,000 recovery rounds passed with 4,765 evictions, 96 retained atlas entries
and a 65,536-byte test atlas. Recovery checked the actual rendered glyph IDs.
The run reported 9,818 ms total CPU and 413 ms recovery CPU; it overlapped the
check suite and is load-test evidence, not a comparative speed result. The
macOS runner does not yet supply RSS for this benchmark.

### Application startup protocols

Implemented Kiwi-specific XTVERSION, configured-theme query/subscription and
application Escape-key mode, including input encoding, Kitty precedence,
mode queries, save/restore and resets. Invalid forms remain observable.
`make check` passed 491 Lua tests across 108 suites, 16 PTY tests, and the
remaining readiness/terminfo/CLI/fuzz/syntax gates. Headless core tests passed.

The strict native daily-driver gate passed on macOS x86_64 / Intel Iris Plus
655 / Metal with tmux 3.8, Neovim, Vim, top, Bash/Zsh metadata, hyperlinks,
private clipboard and RGB readback. Fish, Nushell and SSH were explicitly
skipped. This is bounded startup/replay evidence; interactive editing, resize,
physical layouts and Linux/Windows qualification remain incomplete. See
`evidence/2026-10-25-macos-application-startup.json` for the sanitized report.

### Bold and italic text

Font selection now includes weight/slant for primary and fallback fonts.
FreeType synthesis handles missing styles, with independent face/atlas keys;
GPU shaders no longer brighten the foreground to simulate bold. The regular
primary retains authority over cell dimensions. Five native-font tests cover
real Menlo/DejaVu faces, bitmap synthesis, style run boundaries, fallback and
bounded face exhaustion. Linux CI now explicitly installs the tested fonts.

`make check` passed 496 Lua tests across 109 suites and 16 PTY tests, plus the
other existing gates. Targeted tests passed after the final styled fallback
adjustment. The native Metal smoke captured one frame containing all four
styles; this checks pipeline execution, not a pixel-perfect visual comparison.
The extended stress workload cycled four renditions for 5,000 mixed-text rounds
plus 5,000 exact-glyph recovery rounds: 4,877 evictions, 96 retained entries,
20 font faces and a 65,536-byte atlas. CPU time was 19,269 ms overall / 798 ms
recovery; RSS remains unavailable. This workload differs from the preceding
unstyled run, so its CPU result is not a performance regression comparison.
The full report is `evidence/2026-10-25-macos-styled-text-stress.json`.

### Styled and coloured underlines

Five underline styles, SGR 58/59 and terminfo `Su`/`Smulx`/`Setulc` now reach
cell-aligned atlas masks, including spaces and wide continuations. Explicit
colour survives reverse video; indexed colours track palette updates. Strike,
hyperlinks and IME preedit use the same cell-aligned decoration path.

`make check` passed 509 deterministic Lua tests across 112 suites, 16 PTY
tests and the remaining readiness/terminfo/CLI/fuzz/syntax checks. Core checks
passed 284 tests across 56 suites with native loading disabled. Native Metal
readback found 103,197 pixels near the independently selected underline RGB
on blank cells. Both macOS CI jobs now run this bounded framebuffer gate.
This proves that the native pipeline draws the decorations; all-style visual
comparisons, Linux GL execution and cross-DPI qualification remain open.

### Transactional configuration resources

Reload now stages independent terminal state and all pane renderers before
activation. Font/layout/renderer failure releases only candidates. State
adoption preserves the parser's live object identity, incomplete input,
scrollback, alternate screens and callback ownership; host effects and PTY
resize wait until every pane is active. New image textures get independent
residency. Cleanup/PTY errors after activation are reported without tearing
down the replacement sessions. Staging temporarily duplicates retained state
and GPU resources; worst-case reload latency and peak memory remain to measure.

Eight deterministic tests inject font and each-pane renderer failures, check
abort/cleanup, hidden panes, image residency and partial UTF-8 input. `make
check` passed 517 tests across 113 suites, 16 PTY tests and the remaining gates;
core passed 292 tests across 57 suites. The native Metal interaction smoke
injects failure after allocating the first replacement renderer in a three-pane
window, verifies unchanged snapshots/resources, then successfully changes and
resets the font. Automatic watching and visible error feedback remain open.

### Automatic reload and recoverable errors

The WGPU controller watches configuration precedence paths and referenced
themes through kqueue/inotify and the existing readiness worker. Edits are
debounced for 200 ms; invalid saves retain live resources and display a bounded
UTF-8 error in the title until recovery. Missing themes are watched even when
loading fails. An explicit opt-out retains manual reload, and equivalent
settings (including comment-only saves) skip expensive resource replacement.

`make check` passed 523 Lua tests across 114 suites, 16 PTY tests, native
file/readiness watcher tests and the remaining checks. Core passed 298 tests
across 58 suites. The file watcher passed AddressSanitizer/UndefinedBehaviorSanitizer
on macOS with create/overwrite/atomic-rename/delete/recreate, missing parents,
symlink targets, unrelated events and 128 teardown/recreate cycles. The live
Metal smoke passed invalid-save retention, visible title errors, missing-theme
recovery, theme edits, automatic-reload opt-out/manual retry and retained PTY
output. macOS CI runs this smoke; Linux CI runs sanitizer-backed native tests.
The Linux implementation still needs execution on a Linux runner/desktop.

### Reload load baseline and process metrics

Added current RSS on macOS/Linux and monotonic timing, with a native test that
touches 16 MiB and observes resident growth. Existing burst/long-run/text-stress
workloads now sample macOS RSS too. The new reload benchmark stages real fonts,
state/reflow and packed text buffers at 0/2,000/10,000 retained lines, repeatedly
rejects candidates, and asserts unchanged live state plus bounded retained Lua
heap. GPU allocation/presentation and child resize are excluded.

The first five-sample run reached 901 ms palette p95 / 2,813 ms font-resize p95
at 10,000 lines, with the latter reaching 1,582 MiB sampled process RSS. This
is evidence of a responsiveness problem, not a passing performance gate. The
raw report is `evidence/2026-10-25-macos-reload-baseline.json`; optimization and
a comparable rerun are required.

`make check` passed 525 Lua tests across 115 suites, 16 PTY tests, both native
watchers, process metrics and the remaining gates. The native metrics test also
passed AddressSanitizer/UndefinedBehaviorSanitizer locally.

### Reload memory reduction

Reflow position mapping now retains numeric offsets and resolves requested
positions on demand. Font-change transactions avoid copying cells immediately
before reflow replaces them; unchanged-size paths still copy mutable cells.
Immutable grapheme arrays are shared, with extension allocating new arrays.
Failure and equivalence tests cover alternate screens, retained history, wide
and combining text, underline/hyperlink attributes, images and post-commit input.

The same five-sample benchmark at 10,000 lines reduced font-change additional
Lua heap from 1,041 to 395 MiB and sampled peak process RSS from 1,582 to
1,187 MiB. Font-change wall p95 fell from 2,813 to 1,925 ms. Palette wall p95
increased from 901 to 1,033 ms, despite lower CPU time. These costs remain
unacceptable for interactive use; the performance workstream stays open.
The raw rerun is `evidence/2026-10-25-macos-reload-optimized.json`.

`make check` passed 530 Lua tests across 115 suites, 16 PTY tests, native
watcher/process-metrics tests and the remaining checks. Core passed 303 tests
across 58 suites. Native Metal reload and interaction smokes passed their
assertions, including injected second-pane allocation failure and retained
sessions. These runs do not establish Linux or Windows qualification.

### Symlink reload recovery

A native regression reproduced a missed notification when a configuration
symlink's target was deleted and later recreated in another directory. The
watcher now follows bounded relative/absolute link chains, including directory
components, and watches alias and target parents while a target is missing.
Subscriptions are deduplicated, cycles are rejected, and file stamps are
compared field by field instead of comparing structure padding. Native tests
cover target recreation, alias replacement, missing target directories and
nested links, including AddressSanitizer/UndefinedBehaviorSanitizer on macOS.

### Interactive Vim protocol corrections

Real Vim editing exposed an unanswered `CSI ? 4 m` query. Kiwi now reports the
current modifyOtherKeys level using the
[xterm XTQMODKEYS contract](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).
An additional dispatch bug treated unsupported CSI intermediate bytes as
ordinary commands: for example, `CSI 0 % m` reset text attributes. Unrecognized
intermediate forms now remain observable and leave terminal state unchanged.

[Vim deliberately emits that CSI and `DCS zz ST`](https://github.com/vim/vim/blob/v9.1.1752/src/term.c#L4148)
to check rejection behaviour. Tests verify cursor/attribute preservation,
responses, parser recovery at every byte split, query levels and malformed
requests. The full check passed 533 Lua tests across 115 suites, 16 PTY tests,
native checks and the remaining gates; core passed 306 tests across 58 suites.

### Interactive application workflows

The new `make test-applications` gate drives eight controlled application
workflows through the real PTY and product input/parser/state paths. It checks
edited file contents, Unicode paste, child-reported dimensions, foreground
job interruption, tmux split/zoom/close, pager search/navigation and monitor
exit. Reports retain versions and diagnostics; every successful capture is
replayed with whole, one-byte and eight randomized chunkings against live state.

All eight workflows passed three consecutive local Intel macOS runs. Vim's
deliberate invalid probes remain explicitly counted; all other unsupported
controls fail. Linux and macOS CI now install dependencies, run this gate and
upload bounded controlled recordings. Linux desktop CI also includes automatic
configuration reload on each available GTK WGPU backend. Configured CI gates
are not evidence of remote runner execution. SSH, additional shells, real
keyboard/native presentation and long interactive sessions remain open.
The final local report is
`evidence/2026-10-25-macos-interactive-applications.json`. The complete check
and native automatic-reload smoke also passed after the watcher/protocol changes.

### Real SSH application sessions

Added a temporary key-authenticated OpenSSH server bound only to loopback, with
an isolated client configuration and pinned host key. Four workflows exercise
remote Bash editing/paste/job interruption, remote Neovim, Neovim inside remote
tmux, and local-PTY close propagating HUP to the remote application. Files are
checked independently, resize reaches the remote editor, and captured sessions
must reproduce live state under all ten replay chunkings.

All four passed three consecutive Intel macOS runs using OpenSSH 9.9p2. Linux
and both macOS CI jobs now run the gate and upload bounded evidence separately
from temporary keys/configuration. The report is
`evidence/2026-10-25-macos-ssh-applications.json`. This qualifies loopback TCP
sessions, not heterogeneous remote hosts, adverse networks, or terminfo upload.

### Child terminal identity

Both application presenters now provide `TERM_PROGRAM=Kiwi` and the build
version instead of inheriting the launcher's terminal identity. The interactive
test harness uses the same environment builder. A real-PTY assertion passed
with deliberately conflicting parent identity/version values; all 17 PTY
checks, 306 headless checks, eight local application workflows and the live
macOS interaction/rollback smoke passed.

### Fish and Nushell interactive workflows

Added real fish and Nushell line editing, Unicode paste, resize and external-job
interruption to the PTY harness. All ten local application cases passed on Intel
macOS with fish 4.9.3 and Nushell 0.116.1; the four shell integrations passed
all nine script/launcher tests. The report is
`evidence/2026-10-25-macos-ten-applications.json`.

Nushell's OSC 133 metadata exposed a harness initialization mismatch: replay
applied an initial resize that the live session had not applied, allocating
different row IDs. The harness now applies every recorded resize to the live
state and preserves failure snapshots for diagnosis. No snapshot fields or
protocol failures were excluded. The default gate now requires fish; both
macOS CI jobs additionally require Nushell. Reports from source archives use
`BUILD_REVISION` and explicitly mark Git cleanliness as unavailable.

### Ubuntu build dependency qualification

A fresh Ubuntu 24.04 x86_64 container reproduced a native build failure because
the distribution's GLFW 3.3.10 lacks `glfwGetPlatform`. Bootstrap now rejects
GLFW older than 3.4 with an actionable message. Linux CI and release jobs build
the checksum-pinned 3.4 release with both X11 and Wayland into a private prefix;
the system GLFW is retained. The documented runtime requirement is also 3.4.

With that dependency setup, `make check` passed in the container: 533 Lua tests
across 115 suites, 17 real PTY checks, native readiness/file watcher/process
metrics, terminfo, fuzz, CLI and syntax checks. The old dependency is rejected
before compilation; macOS bootstrap and all edited workflow YAML also passed
their checks. This is Linux headless/native-library evidence, not graphical
desktop, physical hardware or release-package qualification.

### Pager resize synchronization

The first Ubuntu application run passed eight cases and exposed an input race
in the `less` test: its navigation key arrived while the pager processed
SIGWINCH and was discarded. The workflow now waits for the pager to redraw its
prompt on the resized last row before navigating. This passed three consecutive
Ubuntu runs and two macOS runs. Search, resize, page navigation, exit, parser
diagnostics and live/replay comparisons remain asserted. Archive report commands
now suppress Git errors for the whole command group, not just its final command.

### OpenSSH strict ownership on Linux

Ubuntu OpenSSH rejected the fixture's authorized key because its ancestor `/tmp`
is world-writable. The test now creates its private temporary directory beneath
the real account home, explicitly retains `StrictModes yes`, and prints bounded
server diagnostics on failure. It does not change the user's SSH configuration
or relax authentication. All four authenticated SSH workflows passed on Ubuntu
and macOS after the correction; each still checks live/replay equivalence.

The Linux readiness watcher, inotify file watcher and process metrics also
passed AddressSanitizer/UndefinedBehaviorSanitizer. The GTK native host compiled
and passed its ABI check. These checks do not exercise a graphical compositor.

### Editor identity validation

Reviewing the Linux reports found that Ubuntu's `vim` alternative selected
Neovim, so the first run exercised Neovim twice. The harness now checks Vim's
version identity, selects `vim.basic` on Linux when necessary, and permits an
explicit executable override. Actual Vim passed on Linux and macOS; a negative
test explicitly selecting Neovim failed before spawning the wrong editor.
The retained Linux application evidence must come from a rerun with this fix.

### Linux interactive application evidence

The final Ubuntu 24.04 x86_64 run passed all nine default local application
workflows and all four SSH workflows from source revision `b625000`, including
actual Vim 9.1 and Neovim 0.9.5 as separate editors. The reports are
`evidence/2026-10-25-linux-interactive-applications.json` and
`evidence/2026-10-25-linux-ssh-applications.json`. This was an isolated Docker
container with 2 CPUs and 4 GiB memory on the Intel macOS development machine;
times include replay verification and are not performance baselines. The source
was a Git archive with `BUILD_REVISION`; report cleanliness is explicitly
unavailable because there is no `.git` directory. Nushell and native desktop
input/presentation were not exercised in this Linux run.

### Palette reload without copying all retained cells

Unchanged-geometry transactions now fork the scrollback ring and copy only
accessed rows during staging. Activation transfers ownership of unread rows.
History colours resolve from semantic palette slots on access, using one
generation per row; repeated OSC updates do not accumulate deferred operations.
Selection geometry reads row metadata without forcing colour resolution or
cell copies. Screen cells and image residency remain independent, and reflow
with pending colours cannot mutate borrowed source cells.

Five new tests cover rollback, ring eviction/clear, selection, stale palette
resolution across alternate screens and resize, literal RGB/underline colours,
and staged reflow isolation. `make check` passed 538 tests across 115 suites,
17 PTY checks and the remaining native/fuzz/CLI/syntax gates; core passed 311
tests across 58 suites. Native macOS reload now starts with 200 history lines,
views history during theme changes, and verifies updated visible colours.
That smoke and the multi-pane GPU allocation-failure/interaction smoke passed.

A fresh five-sample before/after benchmark at 10,000 history lines reduced
palette staging wall p95 from 497.6 to 11.9 ms and additional sampled Lua heap
from 352.6 to 4.3 MiB. Sampled process RSS fell from 826.1 to 498.1 MiB; retained
history itself still consumes substantial memory. Font-change p95 remained
poor (2,781 to 2,922 ms). These are CPU staging results, excluding GPU work and
activation; deferred history-read costs need separate measurement. Raw reports:
`evidence/2026-10-25-macos-reload-before-lazy-history.json` and
`evidence/2026-10-25-macos-reload-lazy-history.json`.

### Deferred palette work measurement

The reload benchmark now activates replacements, opens a previously unseen
history viewport, then reads every retained row. At 10,000 lines, the five-sample
run measured palette staging at 10.5 ms wall p95, activation at 0.2 ms, the first
history viewport at 0.2 ms, and a complete history read at 56.9 ms. Post-staging
sampled additional Lua heap was 7.1 KiB. Every read asserts the new background;
activation retains the state identity and history count. GPU work remains
excluded. Font-change p95 varied down to 1,413 ms in this run, so individual
timing comparisons remain machine/load-sensitive and still fail a reasonable
interactive responsiveness target. Report:
`evidence/2026-10-25-macos-palette-activation.json`.

### Streaming reflow and sparse destination rows

Reflow emits retained characters directly into destination rows instead of
building temporary anchor/item tables for the entire logical line. The state
path supplies sparse rows, allocating blanks only for uncovered cells. Mapping
still preserves wide-cell gaps, soft wrapping, line identities and row metadata.
A new golden test checks exact gap positions, styled wide continuations, source
isolation and the blank-allocation bound. A one-off deterministic differential
run matched 2,000 randomized documents against the pre-change implementation.

`make check` passed 539 tests across 115 suites, 17 PTY tests and all remaining
gates; core passed 312 tests across 58 suites. Native Metal configuration reload
with visible history and the multi-pane rollback/interaction smokes passed,
followed by all ten local application workflows and four loopback SSH workflows.

In the same five-sample benchmark, 10,000-line font-change staging wall p95 fell
from the preceding run's 1,413 to 695 ms; additional sampled Lua heap fell from
393.2 to 341.1 MiB and sampled process RSS from 1,196.1 to 843.7 MiB. Palette
staging remained 9.6 ms. Large-history font changes are still a noticeable pause,
and these CPU measurements exclude GPU allocation/presentation. Report:
`evidence/2026-10-25-macos-streaming-reflow.json`.

### Linux verification after history/reflow changes

The Ubuntu container reran `make check test-applications test-ssh-applications`
against revision `36820b2`. All 539 Lua tests across 115 suites, 17 PTY tests,
remaining native/fuzz/CLI/syntax gates, nine local application workflows and
four SSH workflows passed. The new palette isolation and sparse reflow tests
ran there too. Retained reports:
`evidence/2026-10-25-linux-reload-interactive-applications.json` and
`evidence/2026-10-25-linux-reload-ssh-applications.json`. Linux graphical reload,
GPU-inclusive latency, large-history memory, and font-change responsiveness
remain open; the container result does not establish any of those claims.

## Numbered tabs and appearance controls (2026-10-25)

- [x] Command+1–9 selects the corresponding native macOS tab; custom bindings
      support workspace tabs. Command+Shift+P opens the default palette.
- [x] Background opacity with opaque foreground text and native surface alpha
      negotiation; verified on GLFW/Metal. GLFW 3.4 X11 is unsupported.
- [x] User-configured WGSL postprocessing, watched shader files, transactional
      failure recovery, static/animated scheduling and two sample effects.
- [x] Native macOS GPU readback for opacity, shader output, resize and recovery;
      live config/shader file edits with a retained PTY and scrollback.
- [x] Linux software Vulkan readback for effects, split panes, resize and invalid
      shader recovery; automated opaque-surface GPU checks in Linux CI.
- [ ] Implement an alpha-capable X11 window path and qualify Wayland; implement
      appearance controls in the experimental GTK GL presenter.

Custom shaders use Kiwi's WGSL function interface, not Ghostty's GLSL interface.
Window blur and shader chains remain unimplemented.

## Incremental literal/regex search (2026-10-25)

Find now scans logical lines in bounded event-loop slices, with Unicode cell
mapping, visible partial-result limits, cancellation and copyable transaction
state. The palette and default regex shortcuts expose it; query input, paste,
key repeats and releases stay isolated from the child while global product
shortcuts remain available. Reusing row/line/NFA buffers keeps the measured
10,000-line workload below 3 MiB temporary Lua heap on macOS and Linux.

Final Lua/core and native raw-PTY search fixtures pass on macOS Metal and Linux
Xvfb/software Vulkan. POSIX differential tests use 5,000 cases per platform;
Linux deliberately uses shallower patterns because libc stalls on some deep
expressions. Complex equivalence on Linux is not inferred from the model/load
checks. See [the complete search evidence](evidence/2026-10-25-search.md) for
bounds, timings, oracle limits and remaining product/desktop gaps. URL hints,
primary selection and the other unchecked workstreams remain open.

## Vi navigation and selection (2026-10-25)

Ctrl+Shift+Space and the palette now expose a separate vi cursor, counted motions,
visual selection, copy, inline find, bracket matching, directional regex Find and
explicit OSC 8 link activation. Long motions and wrapped line/word selections
yield and cancel safely. Stable retained-row indexing avoids whole-history copies;
chunked text extraction avoids a history-sized table of cell references.

Native raw-PTY fixtures pass on macOS Metal and Linux Xvfb with both GLFW and GTK
WGPU hosts. Framebuffer readback verifies rectangular wide-cell highlighting on
Metal and software Vulkan. Headless tests cover transaction copies, cancellation,
limits, reflow, eviction and 500 seeded lifecycle transitions. The 10,000-row model
benchmark uses less than 1.5 MiB temporary heap during scanning, but retains about
357 MiB for the terminal itself; this does not close the general memory/performance
workstream. See [vi evidence and limits](evidence/2026-10-25-vi.md).

At that increment, URL hints, primary selection, actual-desktop/Wayland validation,
Windows and the other unchecked workstreams remained required. Paragraph motions, vi-specific
keymap customization and full Vim behavior are not implemented.

## Keyboard URL hints (2026-10-26)

Open/copy hint actions now discover visible ASCII HTTP(S)/mailto text and OSC 8
destinations, preview the selected target, and require explicit activation.
Discovery and URI validation yield under a shared work budget, report limits,
and discard stale targets. Dense one-cell links use paged labels; badges remain
available when the font cache is full. Global shortcuts and vi return preserve
child-input isolation and ordinary selection.

The final Lua suite passes 608 tests on macOS and Linux. Native GLFW/GTK WGPU
input fixtures and Metal/software-Vulkan framebuffer readbacks pass. The
10,000-row workload scans only viewport/context cells; long-target validation
respects the 4,096-unit slice and 262,144-unit job caps. Raw data, methodology,
qualification boundaries and remaining URI-policy limits are in
[URL hint evidence](evidence/2026-10-26-hints.md). X11 primary selection and all
other unchecked workstreams remain required.

## X11 pointer-primary selection (2026-10-26)

Completing a local mouse selection now publishes a bounded UTF-8 snapshot to
PRIMARY without changing CLIPBOARD. Middle click reads it asynchronously with
application mouse/Shift policy, bracketed-paste framing and cancellation on
focus/pane/input-mode changes. Direct and INCR reads have byte/event/slice limits
and an owner deadline. Cancelled and closing-window conversions drain safely;
one latest click is queued and total process read buffers are capped at 16.

Native checks pass on GLFW/WGPU, GTK/WGPU, GTK GL and GTK GL native-tab routes
under isolated Xvfb. Transfer tests include 1 MiB INCR, malformed/stalled owners,
Latin-1 fallback and sanitizers. Full Lua checks pass 617 tests on Linux/macOS.
This work also fixes an existing GLFW error ABI mismatch and GTK's swapped
middle/right buttons and missing pointer modifiers. See the
[complete evidence](evidence/2026-10-26-primary-selection.md) and
[ownership policy](adr/0043-x11-primary-selection.md).

Keyboard-primary conveniences and actual X11/Wayland desktop qualification remain
open, alongside the other unchecked workstreams. These are bounded transfer/load
checks, not a displayed-latency or performance comparison.

### Keyboard-primary extension

Linux Shift+Insert / Ctrl+Shift+Insert and palette/custom actions now expose
asynchronous primary paste and explicit primary copy. Completed vi selections
publish automatically when focused and generation-valid; refocusing an existing
selection does not reclaim ownership. Find paste captures the query and remaining
byte budget and cancels if the query changes, without PTY fallback.

The extended native fixture passes all four Linux host routes. Full/core suites
pass 621/390 tests on Linux and macOS; the preceding pointer-only statement about
missing keyboard conveniences is superseded. Actual-desktop/Wayland qualification
and the other unchecked non-Windows workstreams remain open.

### Colour emoji and fallback placement

Implemented a fixed RGBA atlas, bitmap-strike scaling, emoji presentation
preference, bounded candidate retries, one reusable colour face per rendition,
and cluster placement anchored to terminal columns. Native BGRA pixels retain
colour and alpha; grayscale masks and decoration coverage remain intact.
Missing clusters preserve their original text and display a placeholder.

Both hosts pass 633 full deterministic tests; 396 core tests pass with native
loading disabled. Native readback passes on macOS Metal and Linux software
Vulkan through GLFW and GTK, plus GTK GL. Readback checks known half-transparent
colour, foreground independence, grayscale coverage, concealment and actual
Apple/Noto emoji. GTK GL lifecycle also passes. Two 5,000-round stress runs
completed mixed text, ASCII recovery and colour recovery with no glyph failures,
bounded 256 KiB test atlases and RSS growth below the 96 MiB ceiling. The normal
application atlas is now 4 MiB, and full-page uploads remain a performance cost.

Evidence and the qualified font-format/host limits are in
[evidence/2026-10-26-color-glyphs.md](evidence/2026-10-26-color-glyphs.md).
Desktop integration, performance/power and distribution gates remain open;
this text increment does not qualify those workstreams.

### Buffered-input readiness before idle-timer removal

`cb09dac` adds one-shot write readiness when a live PTY has queued input, while
ordinary PTYs and the configuration watcher retain read-only interest. The
worker never reads/writes terminal data; all I/O stays on the UI thread. Interest
masks and descriptor counts are validated before replacing a live watch.

macOS and Linux pass 635 full tests / 125 suites and 398 core tests / 67 suites,
plus the `make check` gates. The native readiness fixture passes ASan/UBSan on
both hosts, covering saturated pipes, drain-triggered wakeups, disarming write
interest, one-shot notification, read/EOF behavior and repeated teardown.

The expanded `make pty-wake-smoke` first observes child output, then saturates a
PTY with 256 KiB of input while a raw-mode child deliberately waits 200 ms before
reading. It uses a two-second host wait and fails if delivery takes 1.5 seconds
or bytes are lost/duplicated. Delivery completed in 267.3 ms on macOS GLFW,
210.8 ms on Linux GLFW, and 214.3 ms on Linux GTK/Xvfb. These are synthetic
readiness checks, not keyboard-to-display latency measurements.

The 50 ms application fallback timer is **still present**. Its remaining users
include Linux GLFW's GLib/AT-SPI dispatch, delayed child reaping after PTY EOF,
and periodic development shader checks. Those must be serviced explicitly
before claiming event-driven idle behavior or lower idle power.

### Linux GLFW accessibility readiness

`39838f3` and `828aab3` bridge the default GLib context into GLFW waits.
Descriptor readiness wakes the host; GLib callbacks remain on the UI thread.
Context ownership spans the wait so cross-thread source attachment also wakes
the host. GLib timer deadlines shorten the wait. Unsupported or excessive
descriptor sets retain a bounded 50 ms fallback.

The isolated native fixture passes ASan/UBSan on Linux, including source
attachment, real descriptor readiness, timer deadlines, quiet idle, descriptor
overflow and 100 teardown cycles. A private D-Bus/AT-SPI fixture serves five
actual text queries without provider polling: the slowest completed in 10.4 ms
with a two-second host wait. A quiet-period check also passes. This qualifies
request dispatch, not screen-reader usability or actual-desktop accessibility.
Both macOS and Linux pass `make check test-core` (635 full / 398 core tests).
The application fallback timer remains pending child-exit and other deadline
work; this increment alone does not establish idle-power improvements.

### Event-driven application waits

The preceding timer-status notes are superseded by `768f7f2`. Live windows now
wait for readiness or explicit deadlines, including indefinitely when quiet.
Buffered input, child exits after EOF and Linux GLib/AT-SPI dispatch have native
wake paths. Unsupported child watches and GLib descriptor sets keep explicit
fallbacks. Rendering, configuration debounce, development shaders, navigation,
PRIMARY transfers and diagnostic runtime limits retain their own deadlines.

Both hosts pass 639 full / 400 core tests. Finite/indefinite readiness tests,
configuration reload, Linux interaction fixtures and all four PRIMARY host
paths pass. The quiet gate observes five wakes in each of three clean macOS
runs, versus 58 in the controlled historical baseline; Linux GLFW/GTK observe
four/five. An earlier macOS 87-wake outlier remains unexplained and is preserved.
This closes the blanket-timer implementation gate, not the remaining performance
measurement, desktop reliability or distribution gates. See
[event-wait evidence](evidence/2026-10-26-event-waits.md) for raw reports and limits.
