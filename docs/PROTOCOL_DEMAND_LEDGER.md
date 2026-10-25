# Protocol demand decision ledger

This ledger records decisions made from the daily-driver corpus. It is not a
feature backlog and does not expand the `xterm-kiwi` terminfo contract. A row
may become an implementation issue only after it has a concrete user-visible
failure or request, a sanitised reproducer, a specified terminal/host boundary,
and the evidence required by [the corpus admission rule](DAILY_DRIVER_CORPUS.md#change-rule).

## Current decisions

| Candidate | Corpus evidence | Boundary | Decision | Reconsider only when |
| --- | --- | --- | --- | --- |
| pixel geometry (`CSI 14 t`) | Linux tmux 3.7b recording queried terminal pixel dimensions. Kiwi already responds when host cell metrics exist; the recording previously omitted those metrics. | terminal state and replay metadata; no terminfo capability | **resolved:** replay resize records now retain cell width/height, so the existing reply replays exactly. | A real client demonstrates an incorrect value after a scale or resize transition; route that to #168 with a minimal recording. |
| theme-update subscription and theme query | tmux 3.7b startup fixture and macOS tmux 3.8 strict native replay | terminal state and host configuration changes | **implemented:** `CSI ? 996 n` reports the configured background's light/dark classification; mode 2031 enables notifications when a host palette changes. Application OSC edits do not trigger notifications. | Qualify actual theme changes on each desktop; extend fixtures for any client discrepancy. |
| xterm version query (`CSI > q`) | tmux startup fixture, PTY round trip and strict native replay | terminal identity | **implemented:** `DCS > | Kiwi(version) ST`, using application build metadata, without identifying as xterm. Invalid parameters and version control characters are rejected. | A real client demonstrates an identity or capability-probing mismatch. |
| application escape-key mode | tmux startup fixture, encoder precedence/reset tests, strict native replay | terminal modes and shared host input encoder | **implemented:** mode 7727 encodes Escape as `ESC O [`; negotiated Kitty keyboard encoding takes precedence. Save/restore, DECRQM and resets are covered. | Qualify physical key/layout paths and interactive tmux/Vim sessions on all platforms. |
| controlled SSH RGB/terminfo probe | The daily-driver suite has a bounded recipe but no controlled endpoint was supplied in the current Linux run. | deployment setup and private terminfo installation, not a terminal sequence | **unavailable:** #165 retains this qualification. | A controlled host is available and the existing private-entry probe can record only the approved redacted result. |

## Sources and evidence limits

- tmux intentionally runs panes under its own `TERM` and requires outer RGB
  capability to be configured separately; see the [tmux FAQ](https://github.com/tmux/tmux/wiki/FAQ).
- tmux 3.7b source sends the observed theme and application-key controls in
  [`tty.c`](https://github.com/tmux/tmux/blob/master/tty.c), and its regression
  suite records the private theme-mode query in
  [`input-replies.sh`](https://github.com/tmux/tmux/blob/master/regress/input-replies.sh).
- [xterm's control-sequence reference](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
  identifies `CSI > q` as XTVERSION. This establishes the query's origin, not
  a reason for Kiwi to impersonate xterm.

- [Contour's theme reporting protocol](https://github.com/contour-terminal/contour/blob/master/docs/vt-extensions/color-palette-update-notifications.md)
  defines the 996 query, 997 replies and mode 2031 subscription. Kiwi reports
  the configured terminal palette (weighted RGB brightness threshold 128),
  which can differ from the OS appearance. Host palette changes produce one
  notification; terminal-output colour changes do not create feedback loops.
- [Mintty's Escape-key documentation](https://github.com/mintty/mintty/wiki/Tips#avoiding-the-escape-key-timeout)
  specifies mode 7727 and `ESC O [`.

The minimal local evidence is `tmux-client-queries`. It is chunk-invariant and
contains no captured shell, host, clipboard, or connection contents. The
2026-10-25 macOS x86_64 native run passed tmux 3.8, Neovim, Vim, top, clipboard,
hyperlink, shell-metadata and RGB-readback probes. Fish, Nushell and controlled
SSH were skipped. Interactive input and Linux desktop qualification remain
open. Unknown-control checks have not been waived.
