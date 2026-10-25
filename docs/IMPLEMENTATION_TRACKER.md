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
- [ ] Preserve reproducible captures and automate regression gates in CI.

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
