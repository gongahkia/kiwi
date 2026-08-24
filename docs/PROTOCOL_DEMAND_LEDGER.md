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
| theme-update subscription and theme query | tmux 3.7b sends its private theme controls at client attach; tmux's own source couples the subscription and query. The current capture has no user-visible failure beyond the strict unknown-control qualification gate. | terminal state plus a host-owned appearance-change notification; any reply would assert an appearance policy | **deferred:** Kiwi has no specified terminal-theme event or native appearance qualification on both targets. Silently accepting the control would make tmux believe updates are available. | A tmux or other client has a reproducible theme failure and the required reply/event semantics are sourced, fixtureed, and qualified on Linux and macOS. |
| xterm version query (`CSI > q`) | The same tmux capture queries terminal version; xterm documents this as XTVERSION. | terminal identity and compatibility probing; no terminfo capability | **deferred:** a fabricated xterm identity would invite unsupported feature assumptions, while a Kiwi-specific identity has no demonstrated client requirement. | A client needs a documented response and its feature decision is covered by a bounded fixture without widening advertised compatibility. |
| application escape-key mode | tmux 3.7b enables its private application escape-key mode on attach. The capture has no input repro showing that Kiwi's existing legacy/Kitty behavior is wrong. | host key-event mapping and input encoder, not parser-only state | **deferred:** no parser no-op or synthetic key mapping. This belongs to the real-layout evidence route in #172 if a client-facing input failure is captured. | A representative physical-key/layout capture demonstrates a mismatch, including modifier and application-mode restoration behavior. |
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

The minimal local evidence is `tmux-client-queries`. It is chunk-invariant and
contains no captured shell, host, clipboard, or connection contents. The
compatibility suite remains failed while deferred controls appear, because a
clean replay must mean exactly that rather than a parser counter being waived.
