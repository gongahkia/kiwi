# ADR 0009: own the Kiwi TERM and terminfo contract

## Decision

Set `TERM=kiwi` for children and maintain `terminfo/kiwi.ti` under version control. Build a project-local database with `tic` and pass it with `TERMINFO`.

## Rationale

Advertising `xterm-256color` would promise unsupported behavior. Terminfo is part of the compatibility contract, so it must describe the M1 subset rather than borrow another terminal's claim.

## Consequences

M1 advertises 16 colours and only implemented editing, cursor, margin, alternate-screen, and key capabilities. `make check` validates `tic` and `infocmp`; future capability changes require synchronized terminfo and conformance updates.
