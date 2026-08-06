# UX and UI Specification

## 1. UX goals

- Make a functional language approachable without disguising it as blocks.
- Keep code, tactical execution, and explanation visibly connected.
- Preserve keyboard-first efficiency while supporting ordinary mouse interaction.
- Make autonomous execution readable at real-time speed.
- Use compact bitmap presentation without sacrificing code legibility.
- Avoid conventional RTS affordances that imply direct control.

## 2. Main flow

```text
Main menu
 -> campaign or fixture
 -> briefing
 -> squad and equipment
 -> kiwi workbench
 -> compile and validation
 -> mission
 -> debrief and causal debugger
 -> revise or continue
```

The vertical slice may expose `Run fixture`, `Edit policy`, and `Compare runs` directly for development.

### 2.1 Glasshouse entry flow

Glasshouse opens on a briefing that states the recovery-and-extraction
objective, 90-second lockdown, incomplete hostile intelligence, and Lark's
initial 0.5-metre-uncertainty contact. Continuing opens the workbench. Its
canonical role sidebar is Breach, Mender, Scope, then Lark; each role retains
an independent in-memory editor and compile result while the player reviews
another policy. Compilation only produces DSL diagnostics or bytecode metadata;
it does not deploy or execute a policy.

The mission HUD reports `IN PROGRESS`, `SUCCESS` after the squad objective is
extracted, or `FAILURE` when lockdown prevents extraction. These are copied
outcomes, not player controls or new mission phases.

## 3. Kiwi workbench

Recommended layout:

```text
+----------------------+-----------------------------+
| policies / functions | source editor               |
| fixtures             |                             |
| squad roles          |                             |
+----------------------+-----------------------------+
| diagnostics / types  | compile output / trace link |
+----------------------+-----------------------------+
```

### 3.1 Editor MVP

- open and save policy source;
- cursor and selection;
- insertion, deletion, newline, indentation;
- undo and redo;
- clipboard;
- line numbers;
- visible whitespace option;
- syntax token styling;
- error and warning markers;
- diagnostic navigation;
- source-span highlighting from debugger;
- compile shortcut;
- scroll and page navigation.

### 3.2 Deferred editor features

- multi-cursor;
- plugins;
- language server protocol;
- arbitrary themes;
- terminal emulation;
- split editing;
- refactoring suite;
- general project file browser.

### 3.3 Beginner scaffolding

The first policy opens as working code with marked editable decisions. Examples:

```text
let retreat_threshold = 65%  # try changing this
```

The UI provides:

- inline type display;
- short domain documentation;
- valid constructor suggestions;
- match-arm suggestions;
- sample observation values from fixtures;
- compile warnings that explain unhandled situations.

## 4. Mission view

Recommended layout:

```text
+----------------------------------------------------+
| objective / timer / policy version / signal state |
+--------------------------------------+-------------+
|                                      | event feed  |
| tactical map                         | selection   |
|                                      | details     |
|                                      |             |
+--------------------------------------+-------------+
| playback / overlays / bookmark / trace controls   |
+----------------------------------------------------+
```

### 4.1 Map interaction

The player may:

- pan and zoom;
- select an operative, contact, cover point, projectile, objective, or event;
- inspect current policy state summaries;
- toggle overlays;
- issue only scenario-permitted high-level signals.

Selection rings and hover states must not resemble direct command indicators.

### 4.2 Tactical signals

A signal interaction explicitly shows the data being sent:

```text
Issue: AdvanceTo(Region "North Office")
Recipients: squad coordinator
Delivery: next simulation tick
```

The UI should never say “Move squad here” unless the kiwi actually interprets it that way.

Glasshouse offers only `advance` and `hold` signals, addressed either to the
squad or one deployed player operative. The mission HUD shows queued data before
the next authoritative tick and the most recently issued signal afterwards. A
signal is policy input; its recipient may ignore it.

### 4.3 Glasshouse debrief

The debrief lists retained injury consequences in canonical tick and trace-node
order, initially selecting the first. Selecting another retained injury replaces
the detail panel with that consequence's retained causal chain. It does not
imply an authority change or a source edit.

Guided revision follows the selected injury only to an editable player policy.
It retains the archive-bound historical source, then selects and underlines the
matching expression in the current workbench only when the current source text
is exact. If current text differs, it keeps the historical source and does not
apply its old offsets to the editable buffer.

Rerunning Glasshouse reuses the retained initial authority state, seed, tick
rate, and executed player command log. Only newly compiled policy bindings may
differ. The comparison pane remains compatibility-gated and reports the policy,
state, and retained consequence deltas without claiming a fabricated prediction.

## 5. Overlays

MVP overlays:

- line of sight;
- contact confidence and uncertainty;
- cover quality and threat direction;
- intended path;
- selected and rejected intentions;
- projectile path;
- communication links;
- current squad role and assignment;
- suppression;
- objective regions.

Overlays are derived from snapshots and trace data. They do not change authority.
The initial map distinguishes low and high cover, dims damaged cover by its
integrity, draws rays toward owner-local contact estimates, and outlines empty
and exact-position occupied slots. Reservation and predicted movement are not
rendered as occupancy.

The tactical view also draws copied live projectile markers, one-frame copied
impact markers, a short aim indicator, and a suppression ring. Their values are
read-only presentation data: impact markers derive from the current projectile
impact events and never persist in canonical mission state.

## 6. Causal debugger UI

Recommended three-pane layout:

```text
+-------------------+------------------+------------------+
| timeline          | causal chain     | historical source|
| ticks and events  | values and edges | highlighted span |
+-------------------+------------------+------------------+
| run comparison / filters / explanation summary          |
+----------------------------------------------------------+
```

### 6.1 Event selection

Selecting an injury may show:

```text
Immediate cause
  Projectile P19 impacted Operative A2 at tick 418.

Kiwi contribution
  `continue_advance` was selected because danger 62% was below 65%.

Information limitation
  Contact E4 position was 11 ticks old with confidence 78%.

Alternative
  Cover C12 was observed and ranked second because formation distance cost 24%.
```

### 6.2 Source view

Show historical source associated with the run. Highlight:

- decisive expression;
- inputs and values;
- selected branch;
- intention constructor.

Allow navigation up to enclosing functions and downstream to consequences.

### 6.3 Comparison

Side-by-side or overlaid comparison should show:

- source diff;
- first divergent evaluation;
- changed intention;
- changed path or world event;
- changed final consequence.

## 7. Terminal visual direction

### 7.1 Main source font

Use an original readable bitmap font around 8×12 pixels, inspired by classic PC terminal forms and fonts such as BigBlue Terminal without copying unlicensed or incompatible glyph data.

Required distinctions:

```text
0 O
1 I l |
{ [ (
} ] )
- = >
< | >
' `
, . : ;
```

The font must clearly render DSL punctuation, percentages, arrows if used, and diagnostic markers.

### 7.2 Compact telemetry font

Creep may be evaluated for compact labels, sparklines, or micro-panels subject to licence documentation and readability testing. Do not use it for long source lines if its narrow metrics impair scanning.

### 7.3 Rendering

- nearest-neighbour scaling;
- integer scale where possible;
- high-DPI-aware logical canvas;
- no font smoothing for the primary bitmap font;
- fallback glyph indicator for unsupported characters;
- test at common laptop resolutions.

## 8. Visual style

The vertical slice should use a restrained tactical-computer aesthetic:

- strong silhouettes;
- limited palette;
- clear cover edges;
- visible projectile and impact timing;
- subtle scanline or CRT effects only if they do not reduce readability;
- generated or procedural assets kept stylistically consistent;
- no dependence on large animated character sets.

The aesthetic supports the programming fantasy but must not simulate an actual shell terminal.

## 9. Input model

### 9.1 Global

- keyboard and mouse;
- remappable essential actions after MVP;
- no hidden reliance on right-click conventions.

### 9.2 Workbench defaults

- `Cmd/Ctrl+S`: save;
- `Cmd/Ctrl+Enter`: compile;
- `Cmd/Ctrl+Z`: undo;
- `Cmd/Ctrl+Shift+Z`: redo;
- `F8`: next diagnostic;
- `F9`: previous diagnostic;
- `Esc`: close transient panel.

### 9.3 Mission defaults

- WASD or middle-drag: camera;
- wheel: zoom;
- click: inspect;
- number keys: overlays or signal slots;
- space: pause where allowed;
- bracket keys: speed;
- B: bookmark selected event.

## 10. Accessibility

MVP requirements:

- scalable UI and font;
- non-colour indicators for threat, team, and trace-edge types;
- configurable animation intensity;
- pause and speed controls in tutorial and analysis modes;
- readable diagnostic text;
- keyboard navigation for workbench essentials;
- avoid rapid mandatory reaction as the primary challenge.

Later:

- colour-vision presets;
- screen-reader-compatible exported text reports;
- reduced-motion mode;
- alternate font option;
- adjustable trace density.

## 11. Diagnostics tone

Diagnostics should be direct and educational, not jokey or patronising.

Good:

```text
E204: `None` is not handled here.
A contact may be unavailable when no hostile is currently observed.
```

Avoid:

```text
Oops! Your code forgot something silly.
```

## 12. UX acceptance criteria

- A user can compile the provided policy without external editor use.
- A parser or type error is navigable to the exact source span.
- Mission selection does not provide accidental direct commands.
- A consequence can be opened in the debugger within two interactions.
- Historical source is clearly distinguished from current source.
- Font remains readable at target resolutions.
- Graphical and headless runs share the same authority.
