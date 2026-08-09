# Kiwi M1 terminal conformance

Kiwi implements a deliberately scoped xterm/VT-style behavioral subset. It is neither VT100 nor xterm certified, and `TERM=kiwi` advertises only the terminfo capabilities implemented here. Authoritative behavior sources are [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html), [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/), and [ncurses terminfo](https://invisible-island.net/ncurses/man/terminfo.5.html).

## Test corpus

The deterministic corpus is under `src/tests/fixtures/vt/`. Each structured Lua fixture names its source, grid, byte input, parser bounds where relevant, and expected screen/cursor/mode/response state. `test_conformance.lua` checks declared expectations and compares canonical snapshots when input is delivered whole, at every two-chunk split, one byte at a time, and with eight deterministic randomized chunk layouts.

| Fixture | Primary coverage |
| --- | --- |
| cursor-and-tabs | HT, CUP, relative cursor movement |
| erase-and-edit | ED, ICH, DCH |
| sgr-colours | 16-, 256-, RGB-colour SGR, bold, reset |
| wrap-and-scroll | deferred right-margin wrap, IND, bounded history |
| margins-and-origin | DECSTBM and DECOM |
| alternate-and-modes | 1049 screen, cursor visibility, bracketed-paste state, DSR |
| osc-and-strings | OSC 2 ST title and safe DCS discard |
| utf8-and-malformed | split Unicode, invalid UTF-8 replacement, bounded CSI recovery |

`src/tests/fixtures/replay/live-color-cr.jsonl` is a sanitized recording produced by the live Kiwi path. It covers live initial resize, coloured output, SGR reset, carriage-return overwrite, and headless replay.

## Implemented matrix

| Family | Implemented M1 behavior | Terminfo exposure |
| --- | --- | --- |
| C0 | BEL count, BS, HT, LF/VT/FF, CR; NUL/DEL ignored | `bel`, `cr`, `ind`, `nel` |
| ESC | IND, NEL, RI, save/restore cursor, HTS, RIS | `ind`, `ri`, `sc`, `rc`, `nel` |
| cursor CSI | CUU/CUD/CUF/CUB, CNL/CPL, CHA, VPA, CUP/HVP | `cuu`, `cud`, `cuf`, `cub`, `hpa`, `vpa`, `cup`, `home` |
| erase/edit CSI | ED 0/1/2/3, EL 0/1/2, ECH, ICH, DCH, IL, DL | `ed`, `el`, `ech`, `ich`, `dch`, `il`, `dl` |
| scrolling | SU, SD, DECSTBM, IND/RI at margins | `csr`, `ind`, `ri` |
| SGR | reset, bold/faint/italic/underline/inverse/conceal/strike, standard/bright, 256, RGB, default fg/bg | basic 16-colour `setaf`/`setab`, `sgr0`, `bold`, `dim`, `smul`, `rmul`, `rev`, `invis` |
| modes | IRM; DECOM, DECAWM, DECTCEM, DECCKM, bracketed-paste state | `smkx`/`rmkx`, `civis`/`cnorm`; no bracketed-paste terminfo claim |
| screen | primary plus 47/1047/1048/1049 alternate behavior; bounded primary history | `smcup`, `rmcup` |
| replies | DSR 5/6 and DA response subset | not advertised as a terminfo capability |
| OSC | OSC 0/2 titles; OSC 7/8/133 consumed without UI action | not advertised |
| DCS/APC/PM/SOS | bounded discard through ST; no visible payload | not advertised |
| UTF-8 | incremental decoder, split sequence support, deterministic U+FFFD invalid/truncated output | not a width/shaping claim |

## TERM contract

The child environment is `TERM=kiwi`, never `xterm-256color`. `terminfo/kiwi.ti` is the source of truth. `make terminfo` runs `tic -x -o .build/terminfo terminfo/kiwi.ti` and `TERMINFO=.build/terminfo infocmp kiwi`; `make check` runs the same validation. The live app sets `TERMINFO` to this project-local database for its child.

The entry intentionally declares `colors#16`; it does not declare truecolour, italic SGR, hyperlinks, mouse reporting, or extended keyboard protocols. Adding or removing an advertised capability requires updating both the source entry and this matrix.

## Known unsupported/deferred behavior

M1 does not provide character-set designation, width/grapheme correctness, combining marks, shaping, bidi, CJK/emoji fallback, clipboard, mouse protocols, OSC hyperlinks or shell integration UI, images, full reset variants, DECRQM, OSC palette manipulation, sixel/kitty graphics, or exhaustive DEC private mode behavior. Italic state is retained but has no dedicated italic geometry in the M1 bitmap renderer. Unknown sequences increment counters and retain at most 16 structured samples; control-string payloads are not logged.

## VTTEST workflow

If the system package provides `vttest`, run `make vttest` from an interactive graphical session. The target builds the local terminfo entry, starts `vttest` under `TERM=kiwi`, and leaves interactive case selection to the tester. It is a diagnostic workflow, not a certification claim; the full suite is not required for M1.

## Observed native application smoke

On 2026-08-10, the native GLFW window was exercised with `/bin/sh -i` through an OS virtual keyboard. The recorded session verified text input/Enter, Backspace, normal left/right arrows, Ctrl+C interrupting `sleep 5`, `clear`, post-interrupt output, and clean `exit`. Its replay contained 346 parser bytes, 221 actions, zero parser errors/ignored actions, and zero unknown CSI/ESC/OSC counts; after clear, the visible state contained the `clean` command/output and final exit line.

`/usr/bin/top -d 1` visibly rendered its 133×40 process table in the native window. A bounded `/usr/bin/top -n 1 -d 0.1` recording contained 6,408 parser bytes and 5,224 actions with zero parser errors, ignored actions, or unknown CSI/ESC/OSC/DCS counts. This is an observed M1 subset result, not full TUI or xterm compatibility certification.
