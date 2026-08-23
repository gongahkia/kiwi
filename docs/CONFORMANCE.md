# Kiwi M2 terminal conformance

Kiwi implements a deliberately scoped xterm/VT-style behavioral subset. It is neither VT100 nor xterm certified, and `TERM=xterm-kiwi` advertises only the terminfo capabilities implemented here. Authoritative behavior sources are [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html), [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/), and [ncurses terminfo](https://invisible-island.net/ncurses/man/terminfo.5.html).

## Test corpus

The deterministic corpus is under `src/tests/fixtures/vt/`. Each structured Lua fixture names its source, grid, byte input, parser bounds where relevant, and expected screen/cursor/mode/response state. `test_conformance.lua` checks declared expectations and compares canonical snapshots when input is delivered whole, at every two-chunk split, one byte at a time, and with eight deterministic randomized chunk layouts. The corpus covers G0/G1 ASCII, UK, and DEC Special Graphics designation, including SI/SO shifts used by terminfo line drawing.

| Fixture | Primary coverage |
| --- | --- |
| cursor-and-tabs | HT, CUP, relative cursor movement |
| erase-and-edit | ED, ICH, DCH |
| sgr-colours | 16-, 256-, RGB-colour SGR, bold, reset |
| wrap-and-scroll | deferred right-margin wrap, IND, bounded history |
| margins-and-origin | DECSTBM/DECOM plus origin-relative CPR and DECXCPR |
| left-right-margins | DECLRMM/DECSLRM rectangle scrolling and DECRQSS status |
| dec-special-graphics | G0/G1 ASCII, UK, and DEC Special Graphics designation with SI/SO shifts |
| alternate-and-modes | 1049 screen, cursor visibility, bracketed-paste state, DSR |
| reverse-screen | DECSET 5 (`DECSCNM`) presentation-only reverse video and `CSI ! p` (`DECSTR`) soft reset |
| cursor-style-and-sync | DECSCUSR, synchronized output, alternate-screen persistence |
| xterm-reset-tab-modes | TBC/DECST8C tab lifecycle plus XTSAVE/XTRESTORE and DECRQM for the implemented private modes |
| kitty-keyboard | Kitty keyboard query, baseline flags 1/2/8/16 plus macOS alternate-key flag 4, mode stack, alternate-screen isolation, malformed negotiation |
| kitty-graphics | bounded direct-image APC-G transfer and chunk-boundary invariance |
| kitty-graphics-actions | transfer, query, placement, clear, soft delete, and hard delete lifecycle |
| kitty-graphics-composition | visible negative/positive z placement input for renderer assertions |
| kitty-placements | bounded cell-anchor placement, z-index, and stable no-cursor policy |
| mouse-and-focus | DEC mouse tracking, classic/UTF-8/URXVT/SGR encodings, focus activation, reset, unsupported mode accounting |
| osc-and-strings | OSC 2 ST title and safe DCS discard |
| osc8-hyperlinks | OSC 8 open/close, stable `id` reuse, and both BEL/ST termination |
| shell-integration | OSC 7 current directory plus OSC 133 A/B/C/D shell markers with BEL/ST termination |
| shell-integration-scripts | captured v1 Bash/Zsh/fish OSC 7/133 emission shape; Nushell when `nu` is installed |
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
| C0 | BEL count, BS, HT, LF/VT/FF, CR; NUL/DEL ignored. Standard LNM (`CSI 20 h/l`) optionally applies CR before LF/VT/FF. | `bel`, `cr`, `ind`, `nel` |
| ESC | IND, NEL, RI, save/restore cursor, HTS, RIS; G0/G1 ASCII, UK, and DEC Special Graphics designation with SI/SO | `ind`, `ri`, `sc`, `rc`, `nel`, `smacs`, `rmacs`, `acsc` |
| cursor CSI | CUU/CUD/CUF/CUB, CNL/CPL, CHA, VPA, CUP/HVP | `cuu`, `cud`, `cuf`, `cub`, `hpa`, `vpa`, `cup`, `home` |
| erase/edit CSI | ED 0/1/2/3, EL 0/1/2, ECH, ICH, DCH, IL, DL; VT220 DECSCA plus visible-screen selective display/line erase (DECSED `?0/1/2J`, DECSEL `?0/1/2K`) for protected cells. Selective saved-line erase (`?3J`) and rectangular selective erase are unsupported. | `ed`, `el`, `ech`, `ich`, `dch`, `il`, `dl` |
| scrolling | SU, SD, DECSTBM, DECLRMM/DECSLRM rectangular scrolling, IND/RI at margins | `csr`, `ind`, `ri` |
| SGR | reset, bold/faint/italic/underline/inverse/conceal/strike, standard/bright, 256, RGB, default fg/bg; colon-form `4:n` underline styles retained as an underline | indexed `setaf`/`setab` through 256 plus direct RGB `setrgbf`/`setrgbb`, `sgr0`, `bold`, `dim`, `smul`, `rmul`, `rev`, `invis` |
| Dynamic colours | OSC 4, 10, 11, and 12 updates/queries; OSC 104, 110, 111, and 112 reset paths | none; these are private terminal controls, not terminfo capability claims |
| modes | IRM and LNM; DECSCNM reverse-screen video (DECSET 5) at the presentation boundary; `CSI ! p` (`DECSTR`) resets the implemented soft-reset subset; declared RQM/DECRQM queries (IRM, LNM; DECCKM, DECSCNM, DECOM, DECAWM, xterm reverse-wrap mode 45, DECBKM, DECLRMM, DECTCEM, alternate-screen, mouse/focus, bracketed-paste, synchronized-output); transactional xterm one-level XTSAVE/XTRESTORE for every queryable implemented private mode; DECTCEM cursor blink; DECSCUSR cursor styles; XTMODKEYS `modifyOtherKeys` levels 0–3; DECKPAM/DECKPNM keypad input; DECBKM backspace/DEL negotiation; Kitty keyboard flags 1/2/8/16 on every host and flag 4 on the macOS Cocoa route; classic/UTF-8/URXVT/SGR mouse and focus reporting | `smkx`/`rmkx`, `civis`/`cnorm`; no cursor-style, bracketed-paste, synchronized-output, extended-keyboard, mouse, or focus terminfo claim |
| screen | primary plus 47/1047/1048/1049 alternate behavior; bounded primary history | `smcup`, `rmcup` |
| selection model | directional row-ID/cell-gap endpoints, wide-cell snapping, scrollback/resize reconciliation, local primary-button pointer gestures, alpha-highlight pass, local copy/paste, detached normalized view | not a terminfo capability |
| scrollback search | bounded exact UTF-8 query, stable row-ID/cell ranges, current-match navigation, stale-result state, semantic current-match alpha pass | not a terminfo capability |
| hyperlinks | bounded OSC 8 cell identity, scrollback/resize/replay retention, safe URI activation, semantic underline affordance | not a terminfo capability |
| replies | DSR 5, CPR (`CSI 6 n`) and DECXCPR (`CSI ? 6 n`) with origin-relative coordinates when DECOM is active, conservative primary/secondary DA subsets, read-only xterm text-area/cell geometry queries (`CSI 14 t`, `16 t`, `18 t`), exact bounded `XTGETTCAP` replies for `Co=256`, `TN=xterm-kiwi`, and `RGB=8` bits/channel, plus bounded XTMODKEYS/XTWINOPS state changes | not advertised as a terminfo capability |
| OSC | OSC 0/1/2 icon/window titles; bounded XTWINOPS 22/23 icon/window title stacks; bounded OSC 8 hyperlinks; bounded advisory OSC 7/133 shell metadata and command lifecycle; on macOS, active local OSC 7 metadata may drive the titlebar proxy URL; default-denied, explicitly opt-in OSC 52 UTF-8 clipboard writes; default-denied OSC 9 notification/progress requests | not advertised |
| DCS/APC/PM/SOS | bounded discard through ST; DCS DECRQSS replies for SGR, DECSTBM, DECSLRM, DECSCUSR, DECSCA, and current page height (DECSLPP) only | all other DCS families, including Sixel, remain discarded and unadvertised |
| UTF-8 | incremental decoder, split sequence support, deterministic U+FFFD invalid/truncated output | not a width/shaping claim |
| Unicode text | Unicode 17 UAX #29 EGCs, raw code-point retention, deterministic width, anchor/continuation grid, HarfBuzz LTR shaping, Fontconfig fallback, bounded glyph-ID alpha atlas | not a terminfo capability |

## TERM contract

The ordinary child environment is `TERM=xterm-kiwi`, never `xterm-256color`.
`terminfo/kiwi.ti` is the source of truth. `make terminfo` runs
`tic -x -o .build/terminfo terminfo/kiwi.ti`, validates
`TERMINFO=.build/terminfo infocmp -x xterm-kiwi`, and feeds its actual indexed
and direct-RGB `tput` output through Kiwi's parser/state. `make check` runs the
same validation. The live app passes the source or installed `TERMINFO` and
`COLORTERM=truecolor` through a child-only environment vector to the native
launch helper, which uses `execvpe` on Linux and PATH-aware `execve` on macOS.
The explicit `kiwi-ssh` fallback instead uses `TERM=xterm-256color` with
`COLORTERM=truecolor` when it cannot prepare the remote entry.

The standalone entry intentionally declares `colors#256`, `Tc`, `RGB`,
`setrgbf`, and `setrgbb`; it declares DEC Special Graphics line drawing through
`smacs`, `rmacs`, and `acsc`, but does not declare italic SGR, hyperlinks,
mouse reporting, or an extended-keyboard terminfo capability. The negotiated
Kitty subset is detected through its runtime query, not terminfo. Adding or
removing an advertised capability requires updating the source entry, its
black-box `tput` fixture, and this matrix.

## Clipboard and OSC 52 policy

OSC 52 is default-denied. Setting `osc52-write = true` (or `KIWI_OSC52_WRITE=1`) explicitly permits only a bounded `c`, `p`, or `s` base64 write after UTF-8 and NUL validation; it cannot read, clear, or query the system clipboard and never receives an OSC reply. The terminal core emits a typed request and the GLFW host revalidates it before its one atomic clipboard call. The parser still bounds every OSC string to 4,096 bytes and neither diagnostics nor effects retain raw OSC payloads beyond that synchronous handoff. Local clipboard behavior is defined in [ADR 0020](adr/0020-clipboard-and-osc52-security-policy.md).

## OSC 9 host-effect policy

OSC 9 is an advisory host-effect request, never a terminal-state command. Kiwi
parses a notification body or a progress update into a typed effect, then a
host-owned policy decides whether it may reach the desktop. Both
`osc9-notifications` and `osc9-progress` default to `off`; their only other
value is `system`. Notification bodies are bounded to 1,024 bytes and reject
NUL, CR, and LF. Progress states `0`, `2`, `3`, and `4` may omit their
percentage; determinate state `1` requires an integer percentage from 0 through
100. The policy carries forward the last accepted percentage for an omitted
host update and keeps bounded kind/status diagnostics only, so rejected
terminal payloads are not retained or printed.

At present, `system` can submit a valid notification through the GTK host's
`GApplication` notification path, using the fixed local identifier
`kiwi-terminal-osc9`. Successful submission is not a guarantee that a desktop
will display it. On macOS, the GLFW/Cocoa route maps OSC 9 progress to a
per-window native titlebar progress indicator: state `0` removes it, state `1`
is normal determinate progress, state `2` is error, state `3` is indeterminate,
and state `4` is paused. The determinate states show the carried/supplied
percentage with the corresponding tooltip. It does not use a global Dock badge,
so independent terminal windows cannot overwrite one another's visible
progress. Cocoa notification delivery and GTK progress remain unavailable and
are explicitly reported rather than silently accepted. The deterministic policy
tests cover default denial, payload validation, submission, unavailability, and
payload-free diagnostics. Native notification delivery and presentation still
need desktop qualification. Kiwi leaves accepted progress visible until a
state-`0` clear request or window teardown; it does not currently apply a stale
progress timeout.

## OSC 8 hyperlinks

Kiwi accepts `OSC 8 ; params ; URI ST|BEL` and the empty `OSC 8 ; ; ST|BEL` close form. It retains at most 4,096 target records and at most 2,048 ASCII UTF-8 bytes per URI. The only activatable schemes are `https`, `http`, and `mailto`; control bytes, spaces, NUL, malformed parameters, non-ASCII URI bytes, unsupported schemes, URI-limit overflow, and a repeated OSC `id` with a different URI reject the open and clear the current link. Opening a valid link replaces the current link. Empty close forms end it. Link cells retain an internal identity through ordinary edits, bounded primary scrollback, resize, and replay; no URI is published through renderer resources or diagnostics.

Links draw an underline from the read-only `terminal.hyperlinks` resource through the glyph pass. `KIWI_HYPERLINK_COLOR` accepts `#RRGGBB` or `#RRGGBBAA` and defaults to `#88C0D0FF`. An explicit `Ctrl+primary-click` activates the link under the pointer when application mouse reporting is inactive; `Ctrl+Shift+O` activates the link under the visible cursor. Both bindings remain local under Kitty keyboard disambiguation and do not write PTY input. Activation revalidates the target then calls detached `xdg-open` on Linux or `open` on macOS without a shell; launch acceptance does not prove that a desktop handler opened the URI. `file`, `data`, `javascript`, custom schemes, previews, hover activation, and automatic opening are intentionally unsupported. [ADR 0026](adr/0026-osc8-hyperlink-policy.md) records the full boundary.

## OSC 7 and OSC 133 shell metadata

Kiwi accepts an OSC 7 `file://host/absolute-path` current-directory advisory
value and OSC 133 `A`, `B`, `C`, `D`, or `D;<0..255>` markers, each terminated
by BEL or ST. OSC 7 is ASCII/UTF-8 validated, limited to 2,048 bytes, and
rejects non-`file` schemes, controls, spaces, NUL, query, and fragment
components. Kiwi does not stat, resolve, or automatically open it. On the
macOS Cocoa route only, active-session metadata with an empty, `localhost`, or
current-host authority becomes `NSWindow.representedURL`; a remote or absent
directory clears that titlebar proxy. This does not treat the URI as proof that
the local or remote path exists, and interactive Finder disclosure remains
manual qualification.

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
Bash/Zsh/fish/Nushell emission order. The application injects supported initial shells
by default without changing dotfiles; manual source blocks remain necessary
after a shell transition or explicit-command launch. Activation, disablement,
and removal are documented in
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
There is no wrapping, keybinding rewrite, renderer resource, or accessibility
export in this milestone. The host command palette is a bounded product action,
not a command-region navigation or terminal-core capability. [ADR 0030](adr/0030-command-region-navigation.md)
defines the full contract.

## Input method status

GLFW character callbacks provide committed Unicode code points, including normal
platform dead-key composition. On macOS, Kiwi additionally installs a bounded
`NSTextInputClient` responder over the GLFW Cocoa view: AppKit marked text is
kept outside the terminal grid, rendered as a transient underlined preedit
overlay, committed through the same PTY input boundary, and anchored to the
active cursor for the candidate window. The native bridge caps each marked or
committed UTF-8 payload at 1,024 bytes and cancels preedit on focus/pane
changes.

Linux's default GLFW host has no native Wayland text-input lifecycle. The
separate GTK4 host does implement one through `GtkIMMulticontext`: it attaches
the context to the terminal widget, validates bounded 1,024-byte UTF-8 preedit
and commit callbacks, resets the context on focus loss, and supplies the active
cursor rectangle for candidate placement. Its Lua host adapter preserves the
same key/text correlation and routes preedit through the transient composition
overlay and commits through the PTY input boundary. `make gtk-input-smoke`
checks that native/Lua callback boundary, but it does not qualify a real Linux
input source, compositor candidate UI, focus/cancellation behavior, or
Kitty-keyboard interaction. The Linux status is therefore partial and still
requires the manual desktop qualification recorded in
[NATIVE_HOSTS.md](NATIVE_HOSTS.md) and
[DAILY_DRIVER_COMPATIBILITY.md](DAILY_DRIVER_COMPATIBILITY.md).
[ADR 0025](adr/0025-wayland-ime-and-window-stack.md) records the shared
bounded composition model and the remaining GLFW/Wayland boundary.

## Selection model

The M4 selection model stores no text payload: it records two directional endpoints as stable row IDs and cell gaps, then exposes a detached normalized `[start, finish)` view. Bounds that land inside a wide-cell continuation snap around the whole cluster; combining code points share their anchor cell. Primary selections follow their row into bounded scrollback, while `history_offset` only changes the viewport. A primary column resize reflows soft-wrapped logical rows and remaps those endpoints before grapheme snapping; the physical scrollback bound still applies, so a selection clears if its reflowed endpoint is evicted or dropped. Alternate-screen resize remains fixed-grid. The inactive screen’s selection is retained but marked non-visible.

When application mouse tracking is inactive, the primary button provides local selection: drag extends an inclusive grapheme-cell range, a double-click selects a documented word run, and a triple-click selects the full physical row. GLFW logical positions map through the current content scale and current cell geometry, then clamp to the current viewport; this maps history rows through the state model instead of reconstructing text in input code. Word characters are ASCII letters, digits, `_`, and any leading scalar from U+0080 onward; punctuation and whitespace select their own grapheme cell. With enabled X10, normal, button-event, or any-event tracking, application reporting takes precedence and Kiwi starts no local selection.

The renderer derives a bounded visible range from those stable endpoints and alpha-blends `terminal/selection` after the cell background but before shaped glyphs; cursor rendering remains last. This keeps selected text readable and wide/combining ownership unchanged. `KIWI_SELECTION_COLOR` accepts `#RRGGBB` (default alpha `70`) or `#RRGGBBAA`; the default is `#5E81AC70`. Selection-only pointer changes request the bounded `selection` redraw reason without marking terminal or text damage. The Linux AT-SPI provider exports those endpoints as read-only UTF-8 character offsets for the active pane; the macOS NSAccessibility element reports the bounded current viewport but does not yet expose selection ranges. Screen-reader behavior remains unverified, and Windows has no native adapter. The full contracts are [ADR 0021](adr/0021-grapheme-aware-selection-state.md), [ADR 0022](adr/0022-pointer-selection-gestures.md), [ADR 0023](adr/0023-selection-render-pass.md), and [ADR 0037](adr/0037-accessibility-semantic-model.md).

`Ctrl+Shift+C` copies the visible, non-empty normalized selection through GLFW's main-thread platform clipboard bridge. It emits the stored anchor glyph once, skips continuation cells, joins soft-wrapped physical rows, and inserts one LF between hard rows; it never copies renderer display substitutions. `Ctrl+Shift+V` reads at most 1,048,576 bytes, rejects unavailable, oversized, NUL-containing bridge data, or invalid UTF-8 input without PTY writes, and otherwise writes exact bytes. When DECSET 2004 is active, it adds exactly one `CSI 200~` / `CSI 201~` pair outside that byte limit. Clipboard diagnostics contain counters and status categories only, never clipboard content. Primary selection, rich formats, automatic synchronization, OSC 52 reads/queries, and a modifier override remain out of scope; the separate bounded OSC 52 write-only subset is opt-in.

## Scrollback search

`Ctrl+Shift+F` opens a title-bar query which consumes UTF-8 character input until `Enter` submits or `Escape` clears it. `Ctrl+Shift+G` and `Ctrl+Shift+R` navigate the current result set forward and backward; these local actions are reserved even under Kitty keyboard disambiguation and never enqueue PTY bytes. Search is exact and case-sensitive over each physical row's stored anchor glyphs, including retained primary scrollback and the active screen. It has a 1,024-byte query bound and retains at most 256 overlapping matches in oldest-to-newest order. A match that begins or ends inside a multibyte glyph maps to the entire anchor cell, including a wide cell's continuation footprint.

The result state is separate from selection. It records its search generation, so terminal-content, scrollback, or resize changes make it explicitly `stale` instead of navigating an inferred result. Empty and no-match queries are likewise explicit. Navigating a retained primary result moves only `history_offset` to reveal that row; it does not alter terminal content, selection endpoints, or terminal input. `terminal.search` exposes count, current index/status, bounded visible range descriptors, and a current viewport range but no query text. The `terminal/search` alpha pass renders the current match after selection and before glyphs; `KIWI_SEARCH_COLOR` accepts `#RRGGBB` (default alpha `70`) or `#RRGGBBAA`, with default `#EBCB8B70`. Search-only input requests the `search` redraw reason without terminal/text damage. The full contract is [ADR 0024](adr/0024-bounded-scrollback-search.md).

## Truecolour decision

Kiwi advertises direct RGB deliberately: the terminfo entry has `Tc`, `RGB`,
`setrgbf`, and `setrgbb`, and live children receive `COLORTERM=truecolor`.
The parser/state has an explicit fixture for colon-form indexed and direct-RGB
SGR, while `make terminfo` proves the sequences emitted by `tput` reach that
state without parser errors, ignored actions, or unknown CSI. Its conservative
`XTGETTCAP` runtime reply reports `RGB=8`, the direct-colour channel precision
used by xterm and Ghostty, alongside `Co=256` and `TN=xterm-kiwi`; unrecognised
or mixed queries fail as one bounded `DCS 0 + r` response.

The promotion does not make a general visual or deployment claim. A bounded
macOS Metal framebuffer check observes a known non-palette terminal RGB
background, the native child contract replays cleanly under the promoted
environment, and tmux 3.7b preserves a nested direct-RGB contract on the
current macOS qualification host. Btop is not installed here, so its earlier
application-stream capture has not been requalified under the new TERM value.
On 2026-08-23 an isolated loopback OpenSSH server accepted a fresh client key;
`kiwi-ssh` installed the compiled private entry and its actual remote probe
passed `infocmp`, `tput colors=256`, and `tput setrgbf`. That exercises the
OpenSSH launcher and private-cache path on the same macOS host. A Linux or
external remote deployment remains unqualified. The physical check is
compositor evidence, not display calibration.

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

## Tab stops and private-mode persistence

Kiwi implements horizontal tabulation (`HT`, `CSI Ps I`, and `CSI Ps Z`),
`ESC H` tab-stop set, and xterm's `CSI ? 5 W` (`DECST8C`) default-stop reset.
Default stops are every eight columns beginning at column nine in one-origin
notation. `CSI g`/`CSI 0 g` clears the current stop and `CSI 3 g` clears all
stops; the other TBC parameter values are ignored as xterm does. Kiwi resets
the default stop set during construction, RIS/full state reset, and terminal
resize. These controls are terminal state, not a separate terminfo promise.

`CSI ? Pm s` (`XTSAVE`) and `CSI ? Pm r` (`XTRESTORE`) retain one value per
queryable implemented DEC private mode. Saving validates the complete request
before replacing any retained value; restoring validates the complete request,
then applies retained modes in parameter order. This prevents a malformed
multi-mode request from partially changing Kiwi's saved-mode cache or current
state. The supported values are exactly the private modes that Kiwi reports
through `DECRQM`; `1048` cursor saving is intentionally excluded because it is
a cursor operation rather than a boolean mode. RIS clears the saved-mode cache.
This does not imply support for unimplemented DEC modes or a general xterm
private-mode surface.

## Read-only geometry queries

Kiwi answers xterm window-operation queries `CSI 14 t`, `CSI 16 t`, and
`CSI 18 t` with its focused pane's text-area pixel size, physical cell size,
and grid size respectively. The app updates those metrics after every
pane/font-layout change; the pure core returns pixel replies only after its
host has supplied both metrics. The host never accepts `CSI 8 ; rows ; cols t`
or any other application-driven window operation, so terminal output cannot
resize, move, iconify, raise, lower, or otherwise control a Kiwi window.

## Application keypad

`ESC =` enables DECKPAM and `ESC >` restores DECKPNM. In the former, GLFW and
the public Lua/C input helpers encode keypad digits, decimal point, arithmetic
operators, Enter, and equals as their documented VT220 SS3 forms; in the
latter they encode the matching printable bytes. Kiwi does not receive a
portable Num Lock override from this GLFW path, and it does not invent Kitty
all-keys keypad values: when Kitty all-keys flag 8 is negotiated, that protocol
takes precedence and a public keypad event is explicitly unencoded.

## Kitty keyboard progressive enhancement

Kiwi implements Kitty keyboard progressive-enhancement flags 1
(disambiguate escape codes), 2 (event types), 8 (report all supported keys),
and 16 (report associated text when flag 8 is active) on every host. The macOS
GLFW/Cocoa route additionally implements flag 4 (alternate keys). A client
queries with `CSI ? u`; Kiwi replies with the exact active supported-bit mask,
which is therefore host-specific. `CSI = flags
; mode u` supports replace, set, and clear
operations, while `CSI > flags u` pushes the active screen’s mode and `CSI <
count u` restores it. Each primary/alternate screen owns a separate stack of
at most eight entries; pushing a ninth evicts the oldest. RIS resets both
flags and stacks.

With flag 1 enabled, Escape and modified printable ASCII keys use `CSI
codepoint ; modifier u`; modified cursor, navigation, and F1–F12 keys use the
Kitty-compatible modified functional-key form. Flag 2 appends the supported
press/repeat/release event type to key parameters and permits release reports
for functional keys. Flag 8 emits escape-code reports for supported printable,
Escape, Enter, Tab, and Backspace keys and suppresses the corresponding text
callback; it does not claim layout-derived key identities outside that set.
When flags 8 and 16 are both active, the GLFW boundary holds at most one
printable key for the current event turn, then attaches every non-control
Unicode text callback received in that turn to its Kitty report. An unmatched
physical key is flushed without associated text; a pure IME text event is
represented as `CSI 0;;…u`. The public Lua and C input APIs accept an explicit
bounded scalar sequence for non-GLFW hosts. Flag 16 is cleared if flag 8 is
not active. Modifier values are one plus the Kitty bit field for Shift, Alt,
Ctrl, and Super. Negotiated keyboard mode takes precedence over terminal-local
`Shift+PageUp/Down` history navigation.

For flag 4, the macOS bridge resolves the unshifted and Shift values through
the active Cocoa/Carbon keyboard layout for GLFW's physical scancode, and uses
the GLFW physical key token as the unshifted US PC-101 base value. It emits
`CSI layout:shifted:base;…u` when Shift is active, or `CSI layout::base;…u`
otherwise, only for a key event already encoded by another negotiated Kitty
enhancement. The public Lua and C APIs expose the same three optional scalar
fields so another host can opt in deliberately. GTK and the Linux GLFW route
retain the 1/2/8/16 mask because their current adapters do not provide all
three values with the same contract. A macOS input source without a usable
Unicode keyboard-layout table omits variants for that event rather than
inventing them. Manual non-US-layout qualification remains required before
promoting this partial implementation. This runtime protocol has no terminfo
advertisement.

## Mouse and focus reporting

Kiwi supports DECSET/DECRST X10 (`?9`), normal (`?1000`), button-event
(`?1002`), and any-event (`?1003`) tracking. These are mutually exclusive.
Focus reporting is independent through `?1004`. Encoding is independently
selected by X10 single-byte coordinates (default), UTF-8 coordinates (`?1005`),
SGR cell coordinates (`?1006`), SGR physical-pixel coordinates (`?1016`), or
URXVT decimal coordinates (`?1015`); enabling an encoding replaces the
previous encoding. `?1016` uses the `CSI < Cb ; Px ; Py M` / `m` SGR form with
1-origin physical coordinates relative to the focused pane's clipped viewport.
X10 reporting is press-only. Normal,
button-event, and any-event reports retain xterm button/modifier values;
classic and URXVT reports use `CSI M` forms, while SGR press/motion/wheel is
`CSI < Cb ; Cx ; Cy M` and release is `CSI < Cb ; Cx ; Cy m`. Classic
coordinates are bounded to 223, UTF-8 coordinates to 2,015, and SGR/URXVT
coordinates to 65,535. Button-event motion requires a held supported button;
any-event motion is coalesced to cell transitions; wheel callbacks emit at
most 16 reports. Focus in/out is `CSI I` / `CSI O`.

Xterm alternate-scroll (`?1007`) is independent of mouse encoding. When it is
enabled, the active screen is alternate, and application mouse tracking is
disabled, wheel input emits at most 16 normal `CSI A`/`CSI B` cursor controls.
Primary-screen history remains a Kiwi-local UI operation. Application mouse
tracking always takes precedence over alternate-scroll.

With application mouse tracking enabled, a horizontal GLFW scroll offset emits
xterm's wheel-style button 6 (right) or 7 (left) report in the currently
selected coordinate encoding. Vertical reports are emitted first when one
callback carries both axes; each axis is independently capped at 16 reports.

Highlight, locator, gesture, and touch encoding are not implemented. A
reported mouse event takes precedence over
local selection: enabled X10, normal, button-event, and any-event modes forward
the event to the child and cancel any local drag. Focus loss and any mouse mode
reconfiguration clear held-button and local-drag state. RIS resets tracking,
encoding, and focus state; all are global across primary/alternate screens and
replay deterministically. None are advertised through terminfo.

## Deployment evidence workflow

`make conformance-evidence` is the repeatable command-line starting point for
deployment evidence. It rebuilds and audits the project-local
terminfo entry (`colors#256`, `Tc`, `RGB`, `setrgbf`, and `setrgbb`), runs
a local tmux nesting probe when tmux is installed, and, where a graphical
display is available, records/replays a native VT sequence exercise plus
one-iteration native `top`, Vim mouse, and Neovim keyboard sessions when those
clients are installed. The top, VT, and Vim replays must report zero parser
errors, ignored actions, and unknown CSI/ESC/OSC/string controls. The Neovim
probe verifies its Kitty keyboard query/push/pop exchange and zero parser
errors; its other unsupported startup controls remain separately visible. The
temporary recordings are removed at the end because `top` contains host process
data.

`make daily-driver-compatibility` complements that protocol-focused command
with tmux nesting; installed Bash/Zsh/fish/Nu integration assets; native shell
metadata and OSC 8; Neovim, Vim, and `top` record/replay; an optional controlled
remote SSH terminfo probe; and platform clipboard bridge coverage. Invoke it
with `COMPAT_ARGS='--require-desktop --report artifacts/compatibility.json'` on
a qualification host. Linux public clipboard mutation remains opt-in through
`--allow-public-clipboard`; the suite otherwise records it as manual. Its JSON
report keeps no terminal, shell, clipboard, or recording content, and an
unavailable prerequisite is a skip rather than compatibility evidence.

Every protocol-capability change must add a targeted deterministic fixture,
run `make check`, run this command where its prerequisites are available, and
update the matrix below with the exact command, version/configuration, result,
and caveat. A passing record/replay proves parser/state handling, not visual
fidelity or general application compatibility.

| Surface | Evidence | Result and limit |
| --- | --- | --- |
| Project-local terminfo | `make terminfo`; `TERM=xterm-kiwi TERMINFO=.build/terminfo tput colors`; `TERMINFO=.build/terminfo infocmp -x xterm-kiwi` | Passed on 2026-08-22: `tput colors` returned `256`; the entry declares `Tc`, `RGB`, `setrgbf`, and `setrgbb`; the build-time black-box contract confirms its indexed and direct RGB output reaches Kiwi state. This is local parser/state evidence, not a remote-installation claim. |
| Native truecolour contract | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/truecolour.jsonl -- ./script/truecolour-contract-child'`; `make replay REPLAY_ARGS=--chunk-invariant REPLAY=<temporary>/truecolour.jsonl` | Passed on macOS arm64 on 2026-08-22: the child received `TERM=xterm-kiwi`, `COLORTERM=truecolor`, and `tput colors=256`; its colon-form direct-RGB `tput` output replayed 101 bytes / 86 actions with zero parser errors, ignored actions, or unknown controls under captured, one-byte, and eight randomized output chunk layouts. This is not a physical pixel comparison. |
| Native physical RGB | `make truecolour-framebuffer-smoke` | Passed on macOS arm64 on 2026-08-22: a controlled child filled the terminal with non-palette RGB `18,171,52`; bounded compositor readback found 5,125,680 matching/tolerance pixels and the same modal RGB. This validates Kiwi's terminal background/sRGB surface path, not colour-managed display output, image colour management, a real RGB TUI under `xterm-kiwi`, or SSH. |
| Cocoa Kitty alternate keys | `make cocoa-smoke` | Passed on macOS arm64 on 2026-08-22: the current Carbon keyboard layout produced a bounded non-control unshifted/Shift pair for the physical PC-101 `A` position, which the GLFW/Cocoa bridge passes to the flag-4 encoder. This is bridge evidence only: representative non-US layouts and interactive modified-key behavior remain manual. |
| Cocoa titlebar toolbar | `make cocoa-toolbar-smoke` | Passed on macOS arm64 on 2026-08-23: Kiwi attached a unified AppKit toolbar to its live GLFW/Cocoa window, located the default New Tab item, and dispatched it into the host tab controller. On macOS that request creates a grouped AppKit tab; the direct `make cocoa-smoke` gate separately verifies group membership and next-tab selection. This validates bounded control/action routing, not visual fit-and-finish, interactive toolbar behavior, tab tearing, or native split content. |
| Cocoa OSC 7 proxy URL | `make cocoa-cwd-smoke` | Passed on macOS arm64 on 2026-08-23: the live controller consumed local active-session OSC 7 metadata into `NSWindow.representedURL`, then consumed a remote-host URI and cleared it. This validates bounded bridge routing and the local/remote split, not a user shell's hostname, filesystem existence, or interactive Finder disclosure. |
| Cocoa bounded Apple events | `make cocoa-automation-smoke`; `make release-check` | Passed on macOS arm64 on 2026-08-23: the staged `Kiwi.app` validated `Kiwi.sdef`, ran the terminal controller in the bundle executable process, and dispatched the `new terminal tab` event through the live product-action controller. The reproducible extracted release also passed its LaunchServices launch check. This verifies metadata, process ownership, and in-process callback routing—not external AppleScript sender authorization, a full scripting object model, terminal-text automation, or interactive automation usability. |
| Native shell metadata | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/shell.jsonl -- ./script/shell-integration-child'`; `make replay REPLAY=<temporary>/shell.jsonl` | Passed structurally on 2026-08-10: the 115-byte OSC 7/133 sample replayed as `cwd`, `prompt`, `command_start`, `command_executed`, and `command_finished` with zero parser errors, ignored actions, or unknown controls. The noninteractive child verifies Kiwi's native parser/state path without changing or certifying a user's shell integration configuration. |
| Native shell history | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/history.jsonl -- ./script/shell-integration-history-child'`; `make replay REPLAY=<temporary>/history.jsonl` | Passed structurally on 2026-08-10: the 773-byte 12-command OSC 7/133 stream replayed with 382 actions and zero parser errors, ignored actions, or unknown controls; the derived model retained 12 completed regions. The noninteractive child verifies Kiwi's native retention/replay path without changing or certifying a user's shell integration configuration. |
| Native RGB TUI | `KIWI_MAX_FRAMES=180 make run ARGS='--record <temporary>/btop.jsonl -- /usr/bin/btop'`; replay the capture with `REPLAY_ARGS=--chunk-invariant` | Btop 1.4.7 previously replayed 489,890 bytes / 127,434 actions with zero parser errors, ignored actions, or unknown CSI/ESC/OSC/string controls. Re-run it under `TERM=xterm-kiwi` before treating it as qualification of the promoted contract. It remains application-stream evidence, not a physical truecolour or general-TUI compatibility certification. |
| Native real TUI | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/top.jsonl -- /usr/bin/top -l 1 -s 0'`; `make replay REPLAY_ARGS=--chunk-invariant REPLAY=<temporary>/top.jsonl` | Passed on macOS arm64 on 2026-08-22: the most recent `/usr/bin/top` run replayed 136,235 bytes / 136,235 actions with zero errors, ignored actions, or unknown controls under captured, one-byte, and eight randomized output chunk layouts. Byte/action totals vary with the host process table. This is not a visual-fidelity or full-TUI certification. Linux uses its documented `top -b -n 1 -d 0.1` form. |
| Native VT exercise | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/vt.jsonl -- ./script/vttest-style-child'`; `make replay REPLAY_ARGS=--chunk-invariant REPLAY=<temporary>/vt.jsonl` | Passed on macOS arm64 on 2026-08-23: clear/home, tab clear/reset, XTSAVE/XTRESTORE plus DECRQM replies, standard/indexed/RGB SGR, scrolling margins, alternate screen, cursor visibility/style, synchronized output, Kitty keyboard negotiation, and mouse/focus mode transitions replayed 479 bytes / 185 actions with zero parser errors, ignored actions, or unknown controls under all recorded chunk layouts. It is an automated vttest-style sequence, not the external `vttest` program or a visual certification. |
| Native Kitty graphics | `make kitty-graphics-smoke`; `make kitty-animation-smoke`; or `make conformance-evidence` | The self-contained direct-PNG client passed on macOS arm64 on 2026-08-22: 163,033 bytes / 218 actions replayed with zero parser errors/ignored/unknown controls under all recorded chunk layouts, and GPU timestamp output contained both `terminal/kitty_images_under` and `terminal/kitty_images_over`. The GIF/APNG playback smoke is a separate bounded native check. These verify selected Kiwi protocol streams and pass dispatch, not broad Kitty-client compatibility or pixel-perfect screenshot comparison. |
| Native mouse TUI | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/vim.jsonl -- /usr/bin/vim -Nu NONE -n -c "set ttym=sgr" -c "set mouse=a" -c "redraw!" -c "qa!"'`; `make replay REPLAY_ARGS=--chunk-invariant REPLAY=<temporary>/vim.jsonl` | Passed on macOS arm64 with Vim 9.1 on 2026-08-22: its startup emitted XTMODKEYS, DECTCEM, XTWINOPS title-stack, SGR mouse, and button-event controls; 5,420 bytes / 4,916 actions replayed with zero parser errors, ignored actions, or unknown controls under all recorded chunk layouts. This proves startup-protocol handling, not interactive pointer or modified-key usability. |
| Native keyboard TUI | `KIWI_MAX_FRAMES=120 make run ARGS='--record <temporary>/nvim.jsonl -- /opt/homebrew/bin/nvim -u NONE -n -c "sleep 200m" -c "qa!"'`; `make replay REPLAY_ARGS=--chunk-invariant REPLAY=<temporary>/nvim.jsonl` | Passed on macOS arm64 with Neovim 0.12.4 on 2026-08-22: it emitted the Kitty query `CSI ? u`, a valid progressive-enhancement set `CSI > 3 u`, and `CSI < u`; the most recent run replayed 5,231 bytes / 4,886 actions with zero parser errors, ignored actions, or unknown controls under all recorded chunk layouts. This proves negotiated mode handling, not physical-key usability. |
| Daily-driver application corpus | `make daily-driver-compatibility COMPAT_ARGS='--require-desktop --report <temporary>/compatibility.json'` | Passed on macOS arm64 on 2026-08-23 with the GLFW/Cocoa host: local terminfo, tmux 3.7b nesting, Bash/Zsh/fish/Nushell prompt metadata, native shell-metadata and OSC 8 recordings, the private clipboard bridge, physical RGB readback, Neovim Kitty-keyboard negotiation, Vim mouse-mode startup, and `top` all passed. A separate run against an isolated loopback OpenSSH server also passed the private-terminfo probe. The privacy-bounded report retained no terminal, shell, clipboard, recording, destination, or connection-option contents; its network field explicitly recorded the host-redacted controlled SSH probe. This consolidates bounded application-stream evidence; it does not qualify interactive input, visual fidelity, an external or Linux remote deployment, or a Linux desktop. |
| Native AT-SPI provider | `make accessibility-provider-smoke` | Passed structurally on 2026-08-17: the live provider completed registry `Socket.Embed`; an external D-Bus client found its Kiwi application root and terminal child, read the child process's OSC 2 title as the terminal accessible name, read the bounded sentinel viewport, observed a positive character count, and received a `TextChanged` event. This is protocol evidence, not a screen-reader usability certification. |
| Local tmux | `TERM=xterm-kiwi COLORTERM=truecolor TERMINFO=.build/terminfo tmux -L kiwi-evidence new-session ...`; capture its pane and run `tput setrgbf 1 2 3` | Passed on macOS arm64 on 2026-08-22 with tmux 3.7b: the inner session reported `TERM=tmux-256color`, `COLORTERM=truecolor`, `tput colors=256`, and a successful direct-RGB `tput` command. This is nested protocol evidence, not a pixel comparison. |
| vttest | `make vttest` in an interactive graphical session | No access in this environment: `vttest` is not installed. Record selected case names and visual observations before changing a claim. |
| SSH | `make kiwi-ssh SSH_ARGS='--probe --ssh-option Port=2222 -- <controlled-host>'`, then `infocmp -x xterm-kiwi; tput colors; tput setrgbf 1 2 3` | The deterministic suite verifies upload and launch ordering against local SSH/SCP stubs, including preservation of the `tic` directory path. On macOS arm64 on 2026-08-23, an isolated loopback OpenSSH server accepted a fresh client key; Kiwi uploaded the compiled private entry and the actual remote probe passed `infocmp`, `tput colors=256`, and `tput setrgbf`. This qualifies the launcher path against OpenSSH on the same host, not a Linux or external remote deployment. |

## Unicode conformance

`make test-unicode` runs all 766 cases from the checked-in official Unicode 17.0.0 `GraphemeBreakTest.txt`. The ordinary deterministic suite also runs Kiwi-owned width fixtures, chunk-boundary invariance, combining extensions, variation-selector width changes at the right margin, CJK overwrite/erase, wide-cell anchor/continuation invariants through overwrite/erase/edit/resize/scroll/alternate/reset, cluster bounds, state snapshots, HarfBuzz output against `hb-shape` when available, shaped-glyph inspector mapping, cache invalidation after font/feature/fallback/resize/screen/reset changes, CJK fallback caching, bounded glyph/negative cache behavior, fallback face-cache degradation, optional Nerd Font glyph caching, and native-text benchmark/stress schemas.

M2 terminal-width outcomes are deterministic rather than a claim to emulate the host libc or another terminal. It treats EAW W/F and documented emoji sequences as 2 cells, defaults EAW A and private-use to 1, and supports `KIWI_AMBIGUOUS_WIDTH=2` at startup. The full policy, data provenance, and resource bounds are in [TEXT.md](TEXT.md).

## Known unsupported/deferred behavior

M2 does not provide bidi/reordering, a Unicode line-break algorithm, color emoji/COLR/CBDT/SVG composition, full private-use font coverage guarantees, touch or gesture mouse protocols, OSC hyperlink previews, file/custom-scheme activation, OSC shell integration UI, Sixel, video, broader Kitty graphics support, or exhaustive DEC private mode behavior. Kitty alternate-key flag 4 is partial and macOS-only; it needs manual real-layout qualification and is deliberately absent from GTK/Linux capability masks. RQM/DECRQM replies are limited to Kiwi's implemented IRM and DEC modes; an unrecognized mode reports status `0`, and no reply implies support for any omitted mode. Primary column resize reflows bounded soft-wrapped text, but it does not implement bidi or Unicode line breaking and releases fixed Kitty placement anchors rather than distorting their geometry. Kitty flags 1, 2, 8, and 16 are negotiated and encoded through the GLFW and public host paths: disambiguation, press/repeat/release for non-text keys, all-key escape-code reporting, and bounded associated text. OSC 4/10/11/12/104/110/111/112 palette, default-colour, and cursor-colour changes are supported with bounded `#RRGGBB` and `rgb:` values, including queries and updates to retained palette/default cells; remaining OSC colour controls are not. The bounded PNG/APNG/GIF Kitty APC-G transfer/cache, explicit cell-placement, and fixed image-composition subset is specified in [KITTY_GRAPHICS.md](KITTY_GRAPHICS.md). Italic state is retained but has no dedicated italic geometry in the current glyph renderer. Unknown sequences increment counters and retain at most 16 structured samples; control-string payloads are not logged.

## VTTEST workflow

If the system package provides `vttest`, run `make vttest` from an interactive graphical session. The target builds the local terminfo entry, starts `vttest` under `TERM=xterm-kiwi`, and leaves interactive case selection to the tester. It is a diagnostic workflow, not a certification claim; the full suite is not required for M1.

## Observed native application smoke

On 2026-08-10, the native GLFW window was exercised with `/bin/sh -i` through an OS virtual keyboard. The recorded session verified text input/Enter, Backspace, normal left/right arrows, Ctrl+C interrupting `sleep 5`, `clear`, post-interrupt output, and clean `exit`. Its replay contained 346 parser bytes, 221 actions, zero parser errors/ignored actions, and zero unknown CSI/ESC/OSC counts; after clear, the visible state contained the `clean` command/output and final exit line.

`/usr/bin/top -d 1` visibly rendered its 133×40 process table in the native window. A bounded `/usr/bin/top -n 1 -d 0.1` recording contained 6,408 parser bytes and 5,224 actions with zero parser errors, ignored actions, or unknown CSI/ESC/OSC/DCS counts. This is an observed M1 subset result, not full TUI or xterm compatibility certification.
