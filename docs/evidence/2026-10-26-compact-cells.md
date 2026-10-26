# Compact terminal cells, 2026-10-26

Implementation: `4678c89`.

Ordinary ASCII cells were storing a redundant display string and assigning nil
to absent optional fields. In the tested LuaJIT builds, those operations grew
the cells' table storage. The write path now omits the redundant string and
only clears optional fields that exist. A shared cell-copy helper preserves
this representation during overwrite, screen resizing and configuration
staging; reflow likewise avoids inserting absent fields merely to clear them.
Styled cells retain their underline, hyperlink, continuation and display data.
Combining marks still extend ASCII anchors, and leading combining marks still
display with the dotted-circle prefix.

This reduces ordinary cell storage, not the scrollback limit or visible text.
Cells that need additional attributes can still grow; clearing attributes does
not promise to shrink an already enlarged table. It is not a fixed-byte bound
for arbitrary terminal output.

## Memory and reload measurements

The combined benchmark uses one warmup and five samples each for 0, 2,000 and
10,000 history lines. Both candidate reports identify committed source
`4678c89`: macOS records a clean worktree; Linux uses an archive of that commit.
The preceding baseline has identical application code to `c9cc11f`;
the intervening commit changed documentation only.

| Host, 10,000-line font resize | Additional peak Lua heap, before → after | Sampled peak process RSS, before → after | Wall p95, before → after |
| --- | ---: | ---: | ---: |
| macOS Intel | 341.2 → 231.1 MiB | 838.5 → 562.9 MiB | 671.6 → 921.6 ms |
| Ubuntu container | 340.7 → 230.6 MiB | 749.2 → 502.6 MiB | 609.4 → 464.9 ms |

Raw reports: [macOS before](2026-10-26-macos-reload-retention.json),
[macOS after](2026-10-26-macos-compact-cells.json),
[Linux before](2026-10-26-linux-reload-retention.json),
[Linux after](2026-10-26-linux-compact-cells.json).

Memory falls consistently; timing does not establish a reliable improvement.
An earlier [exploratory macOS run](2026-10-26-macos-compact-cells-exploratory.json)
with the uncommitted implementation measured 462.9 ms wall p95, 230.5 MiB peak
Lua allocation and 564.2 MiB sampled process RSS. The recorded committed run
was slower. These small, sequential samples do not control thermal state or
other host activity; no latency speedup is claimed. Both use normal JIT
compilation. All recorded sizes/modes pass the existing 4 MiB rejected-reload
retention gate. GPU allocation, uploads, presentation and PTY resize remain
outside this CPU staging benchmark; sampled RSS is not an OS high-water mark.

## Write-path check

A detached, clean `c9cc11f` checkout and clean `4678c89` ran the same 25-sample,
five-warmup write benchmark sequentially on the macOS host, sharing unchanged
native dependencies. The temporary baseline checkout was removed afterward.

| Workload / phase | CPU p50 before → after | CPU p95 before → after |
| --- | ---: | ---: |
| ASCII parser/state/damage | 1.588 → 0.722 ms | 1.934 → 1.218 ms |
| ASCII parser through glyph records | 4.359 → 3.250 ms | 6.341 → 5.143 ms |
| Mixed Unicode parser/state/damage | 1.908 → 1.335 ms | 2.477 → 2.728 ms |
| Mixed Unicode parser through glyph records | 36.162 → 35.615 ms | 38.914 → 37.211 ms |

Raw [before](2026-10-26-macos-cell-write-before.json) and
[after](2026-10-26-macos-cell-write-after.json) reports preserve every stage,
counter and environment field. Medians improved in these samples, but the
Unicode parser tail worsened slightly. This is diagnostic evidence, not a
statistically established throughput improvement or a displayed-latency claim.

## Regression and application qualification

Three new tests check full cell-rendition copying and clearing, ASCII/combining/
wide-overwrite behavior, and a plain-history/staged-reflow Lua heap budget.
The budget includes row/state/compiler overhead and
[fails on the preceding implementation](2026-10-26-cell-budget-before.txt).
Both hosts pass **655 full tests / 129 suites** and **415 core tests / 71 suites**,
plus fuzz, PTY, native readiness, filesystem, regex-oracle and syntax checks.

Real Bash, Zsh, Fish, Vim, Neovim, tmux, nested Neovim, less and top workflows
pass on both platforms, with resize, input, saved-file and chunk-invariant replay
assertions. Authenticated loopback SSH shell/editor/tmux and disconnect/HUP
checks pass too. Reports:
[macOS applications](2026-10-26-macos-cell-applications.json),
[macOS SSH](2026-10-26-macos-cell-ssh.json),
[Linux applications](2026-10-26-linux-cell-applications.json),
[Linux SSH](2026-10-26-linux-cell-ssh.json).

The first macOS application run failed because Fish was absent. Homebrew had no
compatible bottle. Qualification instead uses the binary from the official
[Fish 4.9.3 app release](https://github.com/fish-shell/fish-shell/releases/tag/4.9.3),
extracted into ignored `.deps/fish-4.9.3`, with its `Contents/Resources/base/usr/local/bin`
directory prepended to PATH for the test process only. The download SHA-256
matched the official release asset digest:
`3619fa92d540ed0dff4816594429290550d21b92226e0523457e5f0242c5e9a8`.
The rerun passes all nine local workflows and the shell-integration script
tests with Bash/Zsh/Fish required. Nushell is not installed or qualified here.

Native reload/shader recovery and color-glyph framebuffer checks pass on macOS
Metal. Linux Xvfb/software rendering passes WGPU reload, GTK GL single-page and
native-tab reload, and WGPU/GTK GL color-glyph readback. These checks do not close
actual-desktop IME, screen-reader, monitor, suspend/resume or distribution gates.
Large-history reload latency and total resident memory remain substantial.
