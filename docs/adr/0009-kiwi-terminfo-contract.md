# ADR 0009: own the Kiwi TERM and terminfo contract

## Decision

Set `TERM=kiwi` for children and maintain `terminfo/kiwi.ti` under version control. Build a project-local database with `tic` and pass it with `TERMINFO`. Remove inherited `COLORTERM` from live children unless Kiwi has independently validated and advertised truecolour.

## Rationale

Advertising `xterm-256color` would promise unsupported behavior. Terminfo is part of the compatibility contract, so it must describe the M1 subset rather than borrow another terminal's claim.

## Consequences

M1 advertises 16 colours and only implemented editing, cursor, margin, alternate-screen, and key capabilities. `make check` validates `tic` and `infocmp`; future capability changes require synchronized terminfo and conformance updates.

The M5 truecolour audit retained this fallback. A local Btop session can emit RGB SGR that Kiwi parses and retains, and the controlled macOS framebuffer smoke now observes a non-palette terminal RGB background, but neither fact is sufficient to advertise truecolour. The physical check is compositor evidence rather than display calibration; the candidate truecolour contract has not been exercised with a real RGB TUI, tmux's nested contract still advertises 256 colours, and no controlled SSH endpoint is available. The PTY builds a child-only environment vector before `forkpty` and passes it to the native launch helper, so launch overrides do not mutate Kiwi's own environment; it uses `execvpe` on Linux and a PATH-aware `execve` route on macOS.
