# Kiwi M2 terminal conformance

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

## Parser/state hostile-input properties

`make test-fuzz` runs a CI-bounded deterministic property suite: five saved
hostile-input fixtures plus 128 generated inputs of at most 512 bytes. It
asserts parser byte progress, final ground state, bounded CSI/string storage,
bounded action count, valid screen/cursor/margin/damage/cluster structure,
bounded scrollback, and chunk-boundary equivalence. `make fuzz` expands to
4,096 inputs of at most 1,024 bytes for local hardening work.

Each failure prints its generated seed and delta-minimized hexadecimal input.
Replay it without guessing chunk boundaries with:

```sh
KIWI_FUZZ_SEED=<seed> KIWI_FUZZ_REPLAY_HEX=<hex> make test-fuzz
```

New parser behavior must add a targeted saved fixture under
`src/tests/fixtures/fuzz.lua`; random cases supplement but do not replace
documented test vectors. The suite checks structural bounds rather than
claiming formal verification or allocator-independent memory totals.

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
| Unicode text | Unicode 17 UAX #29 EGCs, raw code-point retention, deterministic width, anchor/continuation grid, HarfBuzz LTR shaping, Fontconfig fallback, bounded glyph-ID alpha atlas | not a terminfo capability |

## TERM contract

The child environment is `TERM=kiwi`, never `xterm-256color`. `terminfo/kiwi.ti` is the source of truth. `make terminfo` runs `tic -x -o .build/terminfo terminfo/kiwi.ti` and `TERMINFO=.build/terminfo infocmp kiwi`; `make check` runs the same validation. The live app sets `TERMINFO` to this project-local database for its child.

The entry intentionally declares `colors#16`; it does not declare truecolour, italic SGR, hyperlinks, mouse reporting, or extended keyboard protocols. Adding or removing an advertised capability requires updating both the source entry and this matrix.

## Deployment evidence workflow

`make conformance-evidence` is the repeatable command-line starting point for
deployment evidence. It rebuilds and audits the project-local
terminfo entry (`colors#16` and no `RGB`, `Tc`, `setrgbf`, or `setrgbb`), runs
a local tmux nesting probe when tmux is installed, and, where a graphical
display is available, records/replays a native VT sequence exercise plus a
one-iteration native `top` session when `top` is installed. Each replay must
report zero parser errors, ignored actions, and unknown CSI/ESC/OSC/string
controls. The temporary recordings are removed at the end because `top`
contains host process data.

Every protocol-capability change must add a targeted deterministic fixture,
run `make check`, run this command where its prerequisites are available, and
update the matrix below with the exact command, version/configuration, result,
and caveat. A passing record/replay proves parser/state handling, not visual
fidelity or general application compatibility.

| Surface | Evidence as of 2026-08-10 | Result and limit |
| --- | --- | --- |
| Project-local terminfo | `make terminfo`; `TERM=kiwi TERMINFO=.build/terminfo tput colors`; `infocmp -1 kiwi` | Passed: `tput colors` returned `16`; no unvalidated truecolour capability is advertised. |
| Native real TUI | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/top.jsonl -- /usr/bin/top -n 1 -d 0.1'`; `make replay REPLAY=<temporary>/top.jsonl` | Passed structurally on procps-ng 4.0.4: the native session exited and replay reported zero errors, ignored actions, and unknown controls. Byte/action totals vary with the host process table. This is not a visual-fidelity or full-TUI certification. |
| Native VT exercise | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/vt.jsonl -- ./script/vttest-style-child'`; `make replay REPLAY=<temporary>/vt.jsonl` | Passed structurally: clear/home, standard/indexed/RGB SGR, scrolling margins, alternate screen, and cursor visibility all replayed without parser errors, ignored actions, or unknown controls. It is an automated vttest-style sequence run, not the external `vttest` program or a visual certification. |
| Local tmux | `TERM=kiwi TERMINFO=.build/terminfo tmux -L kiwi-evidence new-session ...`; capture its pane | Observed with tmux 3.7b: the inner command received `TERM=tmux-256color`, and `tput colors` returned `256`. tmux owns the nested contract; this does not authorize Kiwi itself to advertise 256 colours or truecolour. |
| vttest | `make vttest` in an interactive graphical session | No access in this environment: `vttest` is not installed. Record selected case names and visual observations before changing a claim. |
| SSH | `TERMINFO=.build/terminfo ssh -o SendEnv=TERM -o SetEnv=TERM=kiwi <controlled-host> 'infocmp kiwi; tput colors'` | No access to a controlled remote host or credentials. No SSH deployment compatibility claim is made. Install the matching terminfo entry remotely before the probe. |

## Unicode conformance

`make test-unicode` runs all 766 cases from the checked-in official Unicode 17.0.0 `GraphemeBreakTest.txt`. The ordinary deterministic suite also runs Kiwi-owned width fixtures, chunk-boundary invariance, combining extensions, variation-selector width changes at the right margin, CJK overwrite/erase, wide-cell anchor/continuation invariants through overwrite/erase/edit/resize/scroll/alternate/reset, cluster bounds, state snapshots, HarfBuzz output against `hb-shape` when available, shaped-glyph inspector mapping, cache invalidation after font/feature/fallback/resize/screen/reset changes, CJK fallback caching, bounded glyph/negative cache behavior, fallback face-cache degradation, optional Nerd Font glyph caching, and native-text benchmark/stress schemas.

M2 terminal-width outcomes are deterministic rather than a claim to emulate the host libc or another terminal. It treats EAW W/F and documented emoji sequences as 2 cells, defaults EAW A and private-use to 1, and supports `KIWI_AMBIGUOUS_WIDTH=2` at startup. The full policy, data provenance, and resource bounds are in [TEXT.md](TEXT.md).

## Known unsupported/deferred behavior

M2 does not provide bidi/reordering, a Unicode line-break algorithm, color emoji/COLR/CBDT/SVG composition, runtime width-policy reflow, full private-use font coverage guarantees, clipboard, mouse protocols, OSC hyperlinks or shell integration UI, images, full reset variants, DECRQM, OSC palette manipulation, sixel/kitty graphics, or exhaustive DEC private mode behavior. Italic state is retained but has no dedicated italic geometry in the current glyph renderer. Unknown sequences increment counters and retain at most 16 structured samples; control-string payloads are not logged.

## VTTEST workflow

If the system package provides `vttest`, run `make vttest` from an interactive graphical session. The target builds the local terminfo entry, starts `vttest` under `TERM=kiwi`, and leaves interactive case selection to the tester. It is a diagnostic workflow, not a certification claim; the full suite is not required for M1.

## Observed native application smoke

On 2026-08-10, the native GLFW window was exercised with `/bin/sh -i` through an OS virtual keyboard. The recorded session verified text input/Enter, Backspace, normal left/right arrows, Ctrl+C interrupting `sleep 5`, `clear`, post-interrupt output, and clean `exit`. Its replay contained 346 parser bytes, 221 actions, zero parser errors/ignored actions, and zero unknown CSI/ESC/OSC counts; after clear, the visible state contained the `clean` command/output and final exit line.

`/usr/bin/top -d 1` visibly rendered its 133×40 process table in the native window. A bounded `/usr/bin/top -n 1 -d 0.1` recording contained 6,408 parser bytes and 5,224 actions with zero parser errors, ignored actions, or unknown CSI/ESC/OSC/DCS counts. This is an observed M1 subset result, not full TUI or xterm compatibility certification.
