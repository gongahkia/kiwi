# Terminal parity implementation

Scope: the seven workstreams requested on 2026-10-25, plus the distribution
work from the preceding assessment. This ledger records implementation and
verification separately. An unchecked item is still required; local macOS
tests do not establish Linux or Windows desktop qualification.

## Text rendering

- [x] Recover bounded glyph storage after saturation without corrupting cached
      rows, other panes, or retained GPU frames; exercise repeated churn.
- [x] Resolve real bold/italic faces, with an explicit synthesis policy.
- [x] Render underline variants and colours, including blank cells.
- [ ] Improve fallback consistency and render colour emoji.
- [ ] Add deterministic layout/bitmap/readback regressions and stress evidence.

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

## Windows

- [ ] ConPTY creation, resize, I/O, cancellation and child lifecycle.
- [ ] Window/GPU integration, input, fonts, clipboard, IME and accessibility.
- [ ] Build, packaging and Windows CI with actual application execution.

## Performance and power

- [ ] Measure startup, input latency, throughput, memory and idle wakeups.
- [ ] Remove unnecessary polling while preserving output and input readiness.
- [ ] Run representative load/soak workloads with bounded resource assertions.
- [ ] Record reproducible baselines and regression thresholds; distinguish CPU
      microbenchmarks from displayed latency and same-machine comparisons.

## Configuration

- [x] Stage and atomically commit font/renderer/configuration replacement on the
      supported WGPU application path; GTK GL prototype parity remains open.
- [x] Debounce automatic file reload and show recoverable configuration errors
      on WGPU; native Linux execution and GTK GL parity remain open.
- [x] Inject resource failures and verify the old session remains usable.

## Search and keyboard navigation

- [ ] Bounded regex search with cancellation and Unicode-aware results.
- [ ] Vi-style navigation/selection and keyboard URL hints.
- [ ] X11 primary selection with explicit ownership and clipboard policy.

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
