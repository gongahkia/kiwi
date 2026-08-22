# ADR 0009: own the Kiwi TERM and terminfo contract

## Decision

Set `TERM=xterm-kiwi` for children and maintain `terminfo/kiwi.ti` under
version control. Build a project-local database with `tic`, pass it with
`TERMINFO`, and set `COLORTERM=truecolor`. The entry is a standalone contract:
it does not inherit a broad xterm entry or retain a `kiwi` compatibility alias.

## Rationale

Advertising `xterm-256color` would promise behavior Kiwi does not implement.
Terminfo is part of the compatibility contract, so it must describe Kiwi's
implemented subset rather than borrow another terminal's claim. The
`xterm-kiwi` name follows the xterm-family naming convention expected by many
terminal applications without implying xterm conformance.

## Consequences

Kiwi advertises its implemented 256 indexed colours plus direct RGB SGR through
`Tc`, `RGB`, `setrgbf`, and `setrgbb`; it continues to advertise only the
implemented editing, cursor, margin, alternate-screen, and key capabilities.
Its deliberately narrow `XTGETTCAP` reply reports `Co=256`, `TN=xterm-kiwi`,
and `RGB=8` bits per direct-colour channel; unknown or mixed requests receive
the standard bounded failure response. `make terminfo` validates compilation,
declared capabilities, and actual `tput` output fed through Kiwi's
parser/state. `make check` includes that validation. Future capability changes
require synchronized terminfo, parser/state fixtures, and conformance updates.

The promotion is grounded in Kiwi's direct-RGB parser/state fixture, native
compositor RGB readback, and a recorded Btop RGB stream. The native direct-RGB
child and tmux 3.7b qualification probes have passed on the current macOS
host; Btop must be requalified under `xterm-kiwi`, and no controlled SSH host
has yet demonstrated the copied entry. The PTY builds a child-only environment
vector before `forkpty` and passes it to the native launch helper, so launch
overrides do not mutate Kiwi's own environment; it uses `execvpe` on Linux and
a PATH-aware `execve` route on macOS.
