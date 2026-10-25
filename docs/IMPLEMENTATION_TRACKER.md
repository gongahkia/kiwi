# Terminal parity implementation

Scope: the seven workstreams requested on 2026-10-25, plus the distribution
work from the preceding assessment. This ledger records implementation and
verification separately. An unchecked item is still required; local macOS
tests do not establish Linux or Windows desktop qualification.

## Text rendering

- [x] Recover bounded glyph storage after saturation without corrupting cached
      rows, other panes, or retained GPU frames; exercise repeated churn.
- [ ] Resolve real bold/italic faces, with an explicit synthesis policy.
- [ ] Render underline variants and colours, including blank cells.
- [ ] Improve fallback consistency and render colour emoji.
- [ ] Add deterministic layout/bitmap/readback regressions and stress evidence.

## Common applications

- [ ] Reproduce and close the recorded tmux protocol qualification failures.
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

- [ ] Stage and atomically commit font/renderer/configuration replacement.
- [ ] Debounce automatic file reload and show recoverable configuration errors.
- [ ] Inject resource failures and verify the old session remains usable.

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
