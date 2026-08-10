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
| cursor-style-and-sync | DECSCUSR, synchronized output, alternate-screen persistence |
| kitty-keyboard | Kitty keyboard query, level-one mode stack, alternate-screen isolation, malformed negotiation |
| mouse-and-focus | DEC mouse tracking/SGR/focus activation, reset, unsupported mode accounting |
| osc-and-strings | OSC 2 ST title and safe DCS discard |
| osc8-hyperlinks | OSC 8 open/close, stable `id` reuse, and both BEL/ST termination |
| shell-integration | OSC 7 current directory plus OSC 133 A/B/C/D shell markers with BEL/ST termination |
| shell-integration-scripts | captured v1 Bash/Zsh/fish OSC 7/133 emission shape |
| osc52-policy | OSC 52 default denial and bounded oversized payload handling |
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
| modes | IRM; DECOM, DECAWM, DECTCEM, DECCKM, bracketed-paste state; DECSCUSR cursor styles; synchronized output; Kitty keyboard level-one disambiguation; SGR mouse/focus reporting | `smkx`/`rmkx`, `civis`/`cnorm`; no cursor-style, bracketed-paste, synchronized-output, extended-keyboard, mouse, or focus terminfo claim |
| screen | primary plus 47/1047/1048/1049 alternate behavior; bounded primary history | `smcup`, `rmcup` |
| selection model | directional row-ID/cell-gap endpoints, wide-cell snapping, scrollback/resize reconciliation, local primary-button pointer gestures, alpha-highlight pass, local copy/paste, detached normalized view | not a terminfo capability |
| scrollback search | bounded exact UTF-8 query, stable row-ID/cell ranges, current-match navigation, stale-result state, semantic current-match alpha pass | not a terminfo capability |
| hyperlinks | bounded OSC 8 cell identity, scrollback/resize/replay retention, safe URI activation, semantic underline affordance | not a terminfo capability |
| replies | DSR 5/6 and DA response subset | not advertised as a terminfo capability |
| OSC | OSC 0/2 titles; bounded OSC 8 hyperlinks; bounded advisory OSC 7/133 shell metadata and command lifecycle; OSC 52 has no clipboard action or response | not advertised |
| DCS/APC/PM/SOS | bounded discard through ST; no visible payload | not advertised |
| UTF-8 | incremental decoder, split sequence support, deterministic U+FFFD invalid/truncated output | not a width/shaping claim |
| Unicode text | Unicode 17 UAX #29 EGCs, raw code-point retention, deterministic width, anchor/continuation grid, HarfBuzz LTR shaping, Fontconfig fallback, bounded glyph-ID alpha atlas | not a terminfo capability |

## TERM contract

The child environment is `TERM=kiwi`, never `xterm-256color`. `terminfo/kiwi.ti` is the source of truth. `make terminfo` runs `tic -x -o .build/terminfo terminfo/kiwi.ti` and `TERMINFO=.build/terminfo infocmp kiwi`; `make check` runs the same validation. The live app passes `TERMINFO` and an absent `COLORTERM` through a child-only environment vector to `execvpe`.

The entry intentionally declares `colors#16`; it does not declare truecolour, italic SGR, hyperlinks, mouse reporting, or an extended-keyboard terminfo capability. The negotiated Kitty subset is detected through its runtime query, not terminfo. Adding or removing an advertised capability requires updating both the source entry and this matrix.

## Clipboard and OSC 52 policy

OSC 52 is default-denied: terminal output cannot read, write, clear, or query the system clipboard, trigger paste, or receive an OSC reply. The parser still bounds every OSC string to 4,096 bytes and records no OSC payload, only bounded command metadata or rejection reasons. Local clipboard behavior and the still-unimplemented future opt-in OSC 52 write modes are defined in [ADR 0020](adr/0020-clipboard-and-osc52-security-policy.md).

## OSC 8 hyperlinks

Kiwi accepts `OSC 8 ; params ; URI ST|BEL` and the empty `OSC 8 ; ; ST|BEL` close form. It retains at most 4,096 target records and at most 2,048 ASCII UTF-8 bytes per URI. The only activatable schemes are `https`, `http`, and `mailto`; control bytes, spaces, NUL, malformed parameters, non-ASCII URI bytes, unsupported schemes, URI-limit overflow, and a repeated OSC `id` with a different URI reject the open and clear the current link. Opening a valid link replaces the current link. Empty close forms end it. Link cells retain an internal identity through ordinary edits, bounded primary scrollback, resize, and replay; no URI is published through renderer resources or diagnostics.

Links draw an underline from the read-only `terminal.hyperlinks` resource through the glyph pass. `KIWI_HYPERLINK_COLOR` accepts `#RRGGBB` or `#RRGGBBAA` and defaults to `#88C0D0FF`. An explicit `Ctrl+primary-click` activates the link under the pointer when application mouse reporting is inactive; `Ctrl+Shift+O` activates the link under the visible cursor. Both bindings remain local under Kitty keyboard disambiguation and do not write PTY input. Activation revalidates the target then calls detached `xdg-open` without a shell; launch acceptance does not prove that a desktop handler opened the URI. `file`, `data`, `javascript`, custom schemes, previews, hover activation, and automatic opening are intentionally unsupported. [ADR 0026](adr/0026-osc8-hyperlink-policy.md) records the full boundary.

## OSC 7 and OSC 133 shell metadata

Kiwi accepts an OSC 7 `file://host/absolute-path` current-directory advisory
value and OSC 133 `A`, `B`, `C`, `D`, or `D;<0..255>` markers, each terminated
by BEL or ST. OSC 7 is ASCII/UTF-8 validated, limited to 2,048 bytes, and
rejects non-`file` schemes, controls, spaces, NUL, query, and fragment
components. It is not decoded, normalized, resolved, opened, displayed, or
treated as proof that a local or remote path exists.

Accepted OSC 133 records are respectively `prompt`, `command_start`,
`command_executed`, and `command_finished`; the optional finish status is an
unsigned value from 0 to 255. Every accepted sequence records active-screen
scope, stable row ID, cursor column, current-directory identity, and a
monotonic logical timestamp. Repeated markers remain individual records.
Malformed forms are rejected, unknown lettered markers are counted separately,
and none mutate terminal text, cursor, process state, or generic unknown-OSC
diagnostics.

Kiwi retains at most 128 directory records and 512 events by default, dropping
the oldest with counters. Canonical replay snapshots retain opaque IDs/events
but omit directory host/path/URI; shell metadata has no renderer resource,
diagnostic payload, or execution privilege. The `shell-integration` fixture
covers both OSC terminators; `shell-integration-scripts` captures the v1
Bash/Zsh/fish emission order. Versioned scripts are explicit opt-in assets,
not automatic shell setup; activation and removal are documented in
[SHELL_INTEGRATION.md](SHELL_INTEGRATION.md). [ADR 0027](adr/0027-bounded-shell-integration-metadata.md)
and [ADR 0031](adr/0031-opt-in-shell-integration-assets.md) define the
boundary.

## Command-region lifecycle

Accepted OSC 133 markers derive one bounded opaque region lifecycle: `A`
starts `prompt`, `B` moves to `command`, `C` moves to `output`, and `D` or
`D;<0..255>` completes it. A record retains only local ID, start scope,
current-directory ID, stable row/cell positions for its roles, optional finish
status, state, and recovery/interruption facts. It never retains command text,
output text, directory URI/path, host, process information, wall-clock time,
or a renderer handle.

Missing B/C markers produce explicit recovery facts; missing A creates a
recovered command/output region; an orphan D is counted; repeated B/C markers
leave the active record unchanged; a new A or incompatible B interrupts the
active record. A marker on the other terminal screen interrupts an active
region at its last position in its original scope before normal transition.
Rows retain at most eight opaque region IDs and move with ordinary primary
scrollback. Region records count tagged versus still-retained rows, reporting
`retained`, `partial`, `evicted`, `truncated`, or `none` coverage. A ninth ID
does not replace an existing one: the row and new region are explicitly marked
truncated. No region pins a row; once retention ends, its position remains
historical metadata for later navigation to resolve or decline.

There are at most 256 retained records by default. Canonical replay snapshots
include opaque region fields/counters and visible-row IDs but no directory or
terminal-text duplication; the existing JSONL replay derives the same state
from recorded bytes. Snapshot output is `v: 1` and observation-only—there is
no snapshot restore API. The read-only `terminal.command_regions` renderer
resource separately retains at most 32 deduplicated boundaries in the active
viewport, each only `{ row, column, role }`; it omits opaque region IDs, row
IDs, command/output text, CWD data, statuses, recovery, timestamps, and
offscreen regions. A descriptor change requests a `command_regions`
invalidation. `KIWI_COMMAND_REGIONS=1` adds an opt-in command/output separator
pass; extension API v1 can observe the descriptor but cannot draw. There is no
persistent store, shell installer, command execution, or command UI. [ADR 0028](adr/0028-stable-command-region-lifecycle.md),
[ADR 0029](adr/0029-command-region-retention-and-snapshot-boundary.md), and
[ADR 0032](adr/0032-bounded-command-region-render-resource.md) define the
boundaries.

## Command-region navigation

`Ctrl+Alt+P/C/O` move to the previous prompt/command/output boundary;
`Ctrl+Shift+Alt+P/C/O` move forward. These reserved local bindings run before
Kitty keyboard encoding and never send PTY bytes. They are explicitly gated on
the primary screen, no negotiated Kitty keyboard mode, and no active search
query. A gated action leaves the viewport unchanged and reports
`alternate-screen`, `keyboard-mode`, or `search-active`; missing/exhausted
targets report `no-region`, `start`, or `end`.

Candidates are deterministically sorted by retained primary document row,
column, and opaque region ID. Repeated same-role navigation advances from the
last region; an initial action is cursor-relative in the live viewport or
top-row-relative in history. Navigation changes `history_offset` only: it does
not modify terminal cells, selection, clipboard, shell metadata, or search
results. An editing search gates navigation; a submitted search remains intact.

`partial` and `truncated` records are eligible only if their exact requested
role position still resolves to a retained primary row. Evicted, missing,
alternate-screen, and incomplete positions are skipped rather than guessed.
There is no wrapping, command palette, keybinding rewrite, renderer resource,
or accessibility export in this milestone. [ADR 0030](adr/0030-command-region-navigation.md)
defines the full contract.

## Input method status

GLFW character callbacks provide committed Unicode code points, including normal
platform dead-key composition, but Kiwi has no production preedit, candidate,
or Wayland text-input lifecycle. The detached bounded composition spike is
research evidence only; it does not activate an IME, alter terminal input, or
claim compositor integration. [ADR 0025](adr/0025-wayland-ime-and-window-stack.md)
records the tested Wayland environment, required lifecycle, and future
platform boundary.

## Selection model

The M4 selection model stores no text payload: it records two directional endpoints as stable row IDs and cell gaps, then exposes a detached normalized `[start, finish)` view. Bounds that land inside a wide-cell continuation snap around the whole cluster; combining code points share their anchor cell. Primary selections follow their row into bounded scrollback, while `history_offset` only changes the viewport. Kiwi does not reflow on resize, so retained rows clamp to the new width; a selection clears if an endpoint row is evicted or dropped. The inactive screen’s selection is retained but marked non-visible.

When SGR application mouse tracking is inactive, the primary button provides local selection: drag extends an inclusive grapheme-cell range, a double-click selects a documented word run, and a triple-click selects the full physical row. GLFW logical positions map through the current content scale and current cell geometry, then clamp to the current viewport; this maps history rows through the state model instead of reconstructing text in input code. Word characters are ASCII letters, digits, `_`, and any leading scalar from U+0080 onward; punctuation and whitespace select their own grapheme cell. With enabled SGR normal, button-event, or any-event tracking, application reporting takes precedence and Kiwi starts no local selection.

The renderer derives a bounded visible range from those stable endpoints and alpha-blends `terminal/selection` after the cell background but before shaped glyphs; cursor rendering remains last. This keeps selected text readable and wide/combining ownership unchanged. `KIWI_SELECTION_COLOR` accepts `#RRGGBB` (default alpha `70`) or `#RRGGBBAA`; the default is `#5E81AC70`. Selection-only pointer changes request the bounded `selection` redraw reason without marking terminal or text damage. Accessibility and a modifier override remain intentionally absent; the full contracts are [ADR 0021](adr/0021-grapheme-aware-selection-state.md), [ADR 0022](adr/0022-pointer-selection-gestures.md), and [ADR 0023](adr/0023-selection-render-pass.md).

`Ctrl+Shift+C` copies the visible, non-empty normalized selection through GLFW's main-thread Linux clipboard bridge. It emits the stored anchor glyph once, skips continuation cells, joins soft-wrapped physical rows, and inserts one LF between hard rows; it never copies renderer display substitutions. `Ctrl+Shift+V` reads at most 1,048,576 bytes, rejects unavailable, oversized, NUL-containing bridge data, or invalid UTF-8 input without PTY writes, and otherwise writes exact bytes. When DECSET 2004 is active, it adds exactly one `CSI 200~` / `CSI 201~` pair outside that byte limit. Clipboard diagnostics contain counters and status categories only, never clipboard content. Primary selection, rich formats, automatic synchronization, OSC 52 writes, and a modifier override remain out of scope.

## Scrollback search

`Ctrl+Shift+F` opens a title-bar query which consumes UTF-8 character input until `Enter` submits or `Escape` clears it. `Ctrl+Shift+G` and `Ctrl+Shift+R` navigate the current result set forward and backward; these local actions are reserved even under Kitty keyboard disambiguation and never enqueue PTY bytes. Search is exact and case-sensitive over each physical row's stored anchor glyphs, including retained primary scrollback and the active screen. It has a 1,024-byte query bound and retains at most 256 overlapping matches in oldest-to-newest order. A match that begins or ends inside a multibyte glyph maps to the entire anchor cell, including a wide cell's continuation footprint.

The result state is separate from selection. It records its search generation, so terminal-content, scrollback, or resize changes make it explicitly `stale` instead of navigating an inferred result. Empty and no-match queries are likewise explicit. Navigating a retained primary result moves only `history_offset` to reveal that row; it does not alter terminal content, selection endpoints, or terminal input. `terminal.search` exposes count, current index/status, bounded visible range descriptors, and a current viewport range but no query text. The `terminal/search` alpha pass renders the current match after selection and before glyphs; `KIWI_SEARCH_COLOR` accepts `#RRGGBB` (default alpha `70`) or `#RRGGBBAA`, with default `#EBCB8B70`. Search-only input requests the `search` redraw reason without terminal/text damage. The full contract is [ADR 0024](adr/0024-bounded-scrollback-search.md).

## Truecolour decision

Kiwi retains the 16-colour terminfo contract. Its parser, state, and renderer retain RGB SGR values, but that implementation fact does not advertise a truecolour capability. `COLORTERM` is deliberately absent from live children even when the launching environment exports it, and `terminfo/kiwi.ti` has no `RGB`, `Tc`, `setrgbf`, or `setrgbb` extension.

Promotion requires all of the following recorded against the candidate build: a native physical RGB comparison using known distinct pixels, a real RGB TUI under that same child contract, a nested tmux session configured for and verified to preserve RGB, and a controlled SSH host with the matching terminfo installed. Any terminfo change must then pass `tic`, `infocmp`, `tput colors`, and the affected TUI probes. This audit has only structural local evidence; the tmux probe exposes `tmux-256color` with 256 colours, and SSH has no controlled authenticated host. The fallback therefore remains intentional rather than an unverified claim.

## Cursor style and synchronized output

Kiwi accepts DECSCUSR (`CSI Ps SP q`) values 0 through 6. Values 0 and 1
mean a blinking block; 2 is a steady block; 3/4 are blinking/steady
underlines; and 5/6 are blinking/steady bars. Other values, additional
parameters, and other CSI intermediates remain visible unknown CSI sequences.
The canonical numeric style is state/replay data and reaches the
`terminal.cursor` semantic descriptor as `style`, named `shape`, and `blink`.
Visible blinking styles schedule one bounded cursor-only redraw every 0.5
seconds; steady or hidden cursors schedule none.

DECSET/DECRST 2026 (`CSI ? 2026 h` / `CSI ? 2026 l`) brackets synchronized
output. While active, parser and terminal-state mutations continue normally,
but the live loop retains the renderer invalidation and does not present an
intermediate terminal frame. `?2026l` permits the current model to be uploaded
and presented; RIS resets the mode. This does not buffer terminal bytes or add
an unbounded damage store. The mode is global across primary/alternate screen
switches, is replayed deterministically, suppresses cursor-blink scheduling,
and has no terminfo advertisement.

## Kitty keyboard disambiguation

Kiwi implements only Kitty keyboard progressive-enhancement flag 1
(disambiguate escape codes). A client queries with `CSI ? u`; Kiwi replies with
`CSI ? 0 u` or `CSI ? 1 u`. `CSI = flags ; mode u` supports replace, set, and
clear operations, while `CSI > flags u` pushes the active screen’s mode and
`CSI < count u` restores it. Each primary/alternate screen owns a separate
stack of at most eight entries; pushing a ninth evicts the oldest. RIS resets
both flags and stacks.

With flag 1 enabled, Escape and modified printable ASCII keys use `CSI
codepoint ; modifier u`; modified cursor, navigation, and F1–F12 keys use the
Kitty-compatible modified functional-key form. Unmodified UTF-8 text and
Enter, Tab, and Backspace keep their legacy bytes. Modifier values are one
plus the Kitty bit field for Shift, Alt, Ctrl, and Super. The mode takes
precedence over terminal-local `Shift+PageUp/Down` history navigation.

Flags 2 (event types), 4 (alternate keys), 8 (all keys), and 16 (associated
text) are deliberately not implemented. They need accurate release, layout,
and text-event correlation that the current GLFW input boundary does not yet
provide. Requested unsupported bits are absent from the subsequent query
reply; applications that do not negotiate flag 1 retain Kiwi’s legacy input
behavior. This runtime protocol has no terminfo advertisement.

## Mouse and focus reporting

Kiwi supports DECSET/DECRST normal (`?1000`), button-event (`?1002`), and
any-event (`?1003`) mouse tracking only with SGR extended encoding (`?1006`).
Focus reporting is independent through `?1004`. SGR reports use exact
one-based cell coordinates: press/motion/wheel is `CSI < Cb ; Cx ; Cy M`,
release is `CSI < Cb ; Cx ; Cy m`, and focus in/out is `CSI I` / `CSI O`.
Button-event motion requires a held supported button; any-event motion is
coalesced to cell transitions; wheel callbacks emit at most 16 reports. When
more than one tracking mode is enabled, `1003` takes precedence over `1002`,
which takes precedence over `1000`; disabling the selected mode restores the
next enabled mode.

No X10, UTF-8 (1005), URXVT (1015), pixel (1016), highlight, horizontal-wheel,
gesture, or touch encoding is implemented. Tracking without `?1006` retains
mode state but emits nothing, rather than sending a legacy encoding that this
contract does not support. A reported mouse event takes precedence over local
selection: enabled SGR normal, button-event, and any-event modes forward the
event to the child and cancel any local drag. Focus loss and any mouse mode
reconfiguration clear held-button and local-drag state. RIS resets tracking,
SGR, and focus state; all are global across primary/alternate screens and
replay deterministically. None are advertised through terminfo.

## Deployment evidence workflow

`make conformance-evidence` is the repeatable command-line starting point for
deployment evidence. It rebuilds and audits the project-local
terminfo entry (`colors#16` and no `RGB`, `Tc`, `setrgbf`, or `setrgbb`), runs
a local tmux nesting probe when tmux is installed, and, where a graphical
display is available, records/replays a native VT sequence exercise plus
one-iteration native `top`, Vim mouse, and Neovim keyboard sessions when those
clients are installed. The top, VT, and Vim replays must report zero parser
errors, ignored actions, and unknown CSI/ESC/OSC/string controls. The Neovim
probe verifies its Kitty keyboard query/push/pop exchange and zero parser
errors; its other unsupported startup controls remain separately visible. The
temporary recordings are removed at the end because `top` contains host process
data.

Every protocol-capability change must add a targeted deterministic fixture,
run `make check`, run this command where its prerequisites are available, and
update the matrix below with the exact command, version/configuration, result,
and caveat. A passing record/replay proves parser/state handling, not visual
fidelity or general application compatibility.

| Surface | Evidence as of 2026-08-10 | Result and limit |
| --- | --- | --- |
| Project-local terminfo | `make terminfo`; `TERM=kiwi TERMINFO=.build/terminfo tput colors`; `infocmp -1 kiwi` | Passed: `tput colors` returned `16`; no unvalidated truecolour capability is advertised. |
| Native truecolour contract | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/truecolour.jsonl -- ./script/truecolour-contract-child'`; `make replay REPLAY=<temporary>/truecolour.jsonl` | Passed structurally: the actual child received `TERM=kiwi`, `COLORTERM=unset`, and `tput colors=16`; a known RGB SGR value replayed with zero parser errors, ignored actions, or unknown controls. This is not a physical pixel comparison. |
| Native shell metadata | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/shell.jsonl -- ./script/shell-integration-child'`; `make replay REPLAY=<temporary>/shell.jsonl` | Passed structurally on 2026-08-10: the 115-byte OSC 7/133 sample replayed as `cwd`, `prompt`, `command_start`, `command_executed`, and `command_finished` with zero parser errors, ignored actions, or unknown controls. The noninteractive child verifies Kiwi's native parser/state path without changing or certifying a user's shell integration configuration. |
| Native shell history | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/history.jsonl -- ./script/shell-integration-history-child'`; `make replay REPLAY=<temporary>/history.jsonl` | Passed structurally on 2026-08-10: the 773-byte 12-command OSC 7/133 stream replayed with 382 actions and zero parser errors, ignored actions, or unknown controls; the derived model retained 12 completed regions. The noninteractive child verifies Kiwi's native retention/replay path without changing or certifying a user's shell integration configuration. |
| Native RGB TUI | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/btop.jsonl -- /usr/bin/btop'`; inspect raw output and replay | Btop 1.4.7 emitted 43,076 RGB SGR sequences while `COLORTERM` was absent; replay retained the colours but reported one parser error and two unknown CSI controls, including unsupported mouse mode `CSI ? 1015 h`. It is evidence that RGB input reaches the renderer path, not sufficient truecolour or general-TUI compatibility evidence. |
| Native real TUI | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/top.jsonl -- /usr/bin/top -n 1 -d 0.1'`; `make replay REPLAY=<temporary>/top.jsonl` | Passed structurally on procps-ng 4.0.4: the native session exited and replay reported zero errors, ignored actions, and unknown controls. Byte/action totals vary with the host process table. This is not a visual-fidelity or full-TUI certification. |
| Native VT exercise | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/vt.jsonl -- ./script/vttest-style-child'`; `make replay REPLAY=<temporary>/vt.jsonl` | Passed structurally: clear/home, standard/indexed/RGB SGR, scrolling margins, alternate screen, cursor visibility/style, synchronized output, Kitty keyboard negotiation, and mouse/focus mode transitions all replayed without parser errors, ignored actions, or unknown controls. It is an automated vttest-style sequence run, not the external `vttest` program or a visual certification. |
| Native mouse TUI | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/vim.jsonl -- /usr/bin/vim -Nu NONE -n -c "set ttym=sgr" -c "set mouse=a" -c "redraw!" -c "qa!"'`; `make replay REPLAY=<temporary>/vim.jsonl` | Passed structurally with Vim 9.2: it emitted SGR mouse and button-event activation; replay reported 5,542 bytes, 4,893 actions, zero errors, ignored actions, and unknown controls. This proves its activation sequence, not an interactive pointer usability claim. |
| Native keyboard TUI | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/nvim.jsonl -- /usr/bin/nvim -u NONE -n -c "sleep 200m" -c "qa!"'`; `make replay REPLAY=<temporary>/nvim.jsonl` | Passed structurally with Neovim 0.11.6 under `TERM=kiwi`: it emitted Kitty `CSI ? u`, `CSI > 1 u`, and `CSI < u`; replay reported 5,117 bytes, 4,769 actions, and zero parser errors. Three ignored actions plus five unknown CSI and one OSC startup control remain outside Kiwi’s documented subset. This proves negotiated mode handling, not physical-key usability. |
| Local tmux | `env -u COLORTERM TERM=kiwi TERMINFO=.build/terminfo tmux -L kiwi-evidence new-session ...`; capture its pane | Observed with tmux 3.7b: the inner command received `TERM=tmux-256color`, `COLORTERM=truecolor`, and `tput colors` returned `256`, even though the outer invocation removed `COLORTERM`. tmux owns this nested contract; it does not authorize Kiwi itself to advertise 256 colours or truecolour. |
| vttest | `make vttest` in an interactive graphical session | No access in this environment: `vttest` is not installed. Record selected case names and visual observations before changing a claim. |
| SSH | `TERMINFO=.build/terminfo ssh -o SendEnv=TERM -o SetEnv=TERM=kiwi <controlled-host> 'infocmp kiwi; tput colors'` | No access to a controlled remote host or credentials; the localhost probe stopped at host-key verification. No SSH deployment compatibility claim is made. Install the matching terminfo entry remotely before the probe. |

## Unicode conformance

`make test-unicode` runs all 766 cases from the checked-in official Unicode 17.0.0 `GraphemeBreakTest.txt`. The ordinary deterministic suite also runs Kiwi-owned width fixtures, chunk-boundary invariance, combining extensions, variation-selector width changes at the right margin, CJK overwrite/erase, wide-cell anchor/continuation invariants through overwrite/erase/edit/resize/scroll/alternate/reset, cluster bounds, state snapshots, HarfBuzz output against `hb-shape` when available, shaped-glyph inspector mapping, cache invalidation after font/feature/fallback/resize/screen/reset changes, CJK fallback caching, bounded glyph/negative cache behavior, fallback face-cache degradation, optional Nerd Font glyph caching, and native-text benchmark/stress schemas.

M2 terminal-width outcomes are deterministic rather than a claim to emulate the host libc or another terminal. It treats EAW W/F and documented emoji sequences as 2 cells, defaults EAW A and private-use to 1, and supports `KIWI_AMBIGUOUS_WIDTH=2` at startup. The full policy, data provenance, and resource bounds are in [TEXT.md](TEXT.md).

## Known unsupported/deferred behavior

M2 does not provide bidi/reordering, a Unicode line-break algorithm, color emoji/COLR/CBDT/SVG composition, runtime width-policy reflow, full private-use font coverage guarantees, Kitty keyboard flags 2/4/8/16 beyond the documented disambiguation subset, legacy/pixel/gesture mouse protocols beyond the documented SGR subset, OSC hyperlink previews, file/custom-scheme activation, OSC shell integration UI, images, full reset variants, DECRQM, OSC palette manipulation, sixel/kitty graphics, or exhaustive DEC private mode behavior. Italic state is retained but has no dedicated italic geometry in the current glyph renderer. Unknown sequences increment counters and retain at most 16 structured samples; control-string payloads are not logged.

## VTTEST workflow

If the system package provides `vttest`, run `make vttest` from an interactive graphical session. The target builds the local terminfo entry, starts `vttest` under `TERM=kiwi`, and leaves interactive case selection to the tester. It is a diagnostic workflow, not a certification claim; the full suite is not required for M1.

## Observed native application smoke

On 2026-08-10, the native GLFW window was exercised with `/bin/sh -i` through an OS virtual keyboard. The recorded session verified text input/Enter, Backspace, normal left/right arrows, Ctrl+C interrupting `sleep 5`, `clear`, post-interrupt output, and clean `exit`. Its replay contained 346 parser bytes, 221 actions, zero parser errors/ignored actions, and zero unknown CSI/ESC/OSC counts; after clear, the visible state contained the `clean` command/output and final exit line.

`/usr/bin/top -d 1` visibly rendered its 133×40 process table in the native window. A bounded `/usr/bin/top -n 1 -d 0.1` recording contained 6,408 parser bytes and 5,224 actions with zero parser errors, ignored actions, or unknown CSI/ESC/OSC/DCS counts. This is an observed M1 subset result, not full TUI or xterm compatibility certification.
