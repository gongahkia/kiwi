# Terminal Compatibility Policy

## 1. Positioning

Stanczyk implements a documented terminal compatibility subset. It must not claim complete VT100, VT220, xterm, Kitty, or iTerm2 compatibility.

Compatibility is organised into profiles. A profile is a named set of parser, mode, colour, input, and rendering behaviour with fixtures and known limitations.

The first profile is `stanczyk-basic-v1`.

## 2. Compatibility principles

- Sequences are supported only when semantics and tests exist.
- Unknown sequences are ignored safely and surfaced in debugger mode.
- Parameter and string lengths are bounded.
- Parser recovery behaviour is deterministic.
- Input chunk boundaries cannot change semantics.
- Host-integrating OSC actions are disabled unless explicitly designed.
- Compatibility additions must not silently alter existing profile behaviour.

## 3. `stanczyk-basic-v1`

### 3.1 Character handling

Required:

- printable ASCII;
- UTF-8 decoding;
- replacement behaviour for malformed UTF-8;
- single-width characters;
- double-width characters using width tables;
- combining marks with a documented initial composition strategy;
- tab expansion using tab stops.

Deferred:

- full grapheme-cluster conformance;
- emoji presentation negotiation;
- complex-script shaping beyond the selected font/rendering strategy;
- bidirectional text.

### 3.2 C0 controls

Required:

- NUL: ignore;
- BEL: emit semantic bell event;
- BS: move cursor left within bounds;
- HT: move to next tab stop;
- LF, VT, FF: line feed according to current mode policy;
- CR: move to column zero;
- ESC: enter escape state;
- CAN and SUB: cancel current sequence and recover;
- DEL: ignore in ground state.

### 3.3 ESC sequences

Required initial subset:

- `ESC 7`: save cursor and relevant state;
- `ESC 8`: restore cursor and relevant state;
- `ESC D`: index;
- `ESC E`: next line;
- `ESC M`: reverse index;
- `ESC H`: set tab stop;
- `ESC c`: terminal reset with documented scope;
- character-set designation sequences may be parsed and ignored until implemented, but must not corrupt state.

### 3.4 CSI cursor movement

Required:

- CUU: cursor up;
- CUD: cursor down;
- CUF: cursor forward;
- CUB: cursor backward;
- CNL: cursor next line;
- CPL: cursor previous line;
- CHA: cursor horizontal absolute;
- CUP/HVP: cursor position;
- VPA: vertical position absolute;

Parameter rules must cover omitted, zero, one, and overlarge values.

### 3.5 Erase and editing

Required:

- ED: erase in display for modes 0, 1, and 2;
- EL: erase in line for modes 0, 1, and 2;
- ECH: erase characters;
- ICH: insert characters;
- DCH: delete characters;
- IL: insert lines within the scrolling region;
- DL: delete lines within the scrolling region;
- SU: scroll up;
- SD: scroll down.

Selective erase and protected cells are deferred.

### 3.6 Margins and scrolling

Required:

- DECSTBM: set top and bottom margins;
- index and reverse-index behaviour within margins;
- line feed scrolling at the bottom margin;
- reset margins on terminal reset and resize according to documented policy.

Left/right margins are deferred.

### 3.7 Rendition

Required SGR support:

- reset;
- bold or increased intensity;
- faint;
- italic;
- underline;
- blink semantic flag, with no requirement to animate by default;
- inverse;
- conceal;
- strike;
- standard 8 foreground and background colours;
- bright 8 colours;
- 256-colour indexed foreground and background;
- 24-bit RGB foreground and background;
- default foreground and background restoration;
- individual attribute resets where practical and tested.

The renderer may approximate bold through font selection or controlled overdraw. This is a rendering decision, not a terminal semantic difference.

### 3.8 Modes

Required initial modes:

- origin mode;
- auto-wrap mode;
- cursor visibility;
- alternate screen variants required by common TUIs;
- application cursor keys as input metadata when PTY input encoding is implemented;
- bracketed paste may be represented later.

Deferred:

- mouse reporting;
- focus reporting;
- modifyOtherKeys;
- Kitty keyboard protocol;
- synchronized output;
- sixel and inline-image protocols.

### 3.9 OSC

Initial behaviour:

- parse and expose terminal title sequences as metadata;
- safely ignore unsupported OSC payloads;
- bound OSC string length;
- surface unsupported OSC commands in debugger mode.

Disabled initially:

- clipboard access;
- notifications;
- file transfer;
- shell integration;
- current-directory trust decisions;
- hyperlink activation.

OSC 8 hyperlink parsing may be added later with inert rendering before click behaviour.

### 3.10 Device queries

The core may parse device-status and device-attribute requests, but response generation belongs to backend/input policy and is deferred unless required by representative TUIs.

Do not emit fabricated compatibility responses merely to satisfy applications.

## 4. Resize policy

On resize:

- dimensions must remain positive and bounded;
- visible rows and columns are adjusted deterministically;
- cursor is clamped;
- margins are reset or clamped according to the accepted implementation ADR;
- scrollback reflow is deferred unless deliberately implemented;
- the alternate screen has no persistent scrollback;
- wide-cell consistency must be repaired at new boundaries.

The first version may use non-reflowing scrollback and visible rows. This limitation must be documented.

## 5. Input encoding

Input generation is a separate layer from output parsing.

Initial PTY input requirements:

- printable UTF-8 keyboard input;
- Enter, Backspace, Tab, Escape;
- arrow keys using normal or application cursor mode;
- Home, End, Insert, Delete, Page Up, Page Down;
- common function keys;
- Control combinations;
- window resize propagation.

Mouse, focus, and advanced keyboard protocols are later work.

## 6. Conformance testing

Each supported sequence requires:

- a minimal fixture;
- parameter-boundary cases;
- arbitrary chunk splitting;
- interaction with margins or modes where relevant;
- malformed-sequence recovery cases;
- expected state digest or focused assertions.

Representative third-party TUI tests supplement but do not replace sequence-level tests.

## 7. Compatibility profile evolution

Changes that only add unsupported sequences may extend `stanczyk-basic-v1` if existing behaviour is unchanged.

Changes that alter existing semantics require:

- a new profile version or explicit migration rule;
- an ADR;
- replay and fixture assessment;
- documentation of affected applications.
