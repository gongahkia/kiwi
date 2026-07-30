# UX and UI Specification

## 1. UX goals

The interface must make a complex programming-and-simulation game feel legible.

Primary goals:

- keep code, world, and consequence visually connected;
- avoid presenting a blank editor to new players;
- expose only contextually relevant concepts;
- make incomplete information visible;
- distinguish program intention from simulation outcome;
- support keyboard-first use without excluding mouse users;
- maintain readable pixel-font rendering.

## 2. Main screen flow

```text
Main Menu
  -> Campaign / Scenario Select
  -> Mission Briefing
  -> Squad Assembly
  -> Doctrine Workbench
  -> Deployment
  -> Live Mission
  -> Mission Result
  -> Causal Debugger
  -> Roster / Next Mission
```

## 3. Doctrine workbench

Recommended layout:

```text
+---------------------------------------------------------------+
| Mission context | Compile | Test | Deploy | Version            |
+----------------------+----------------------+-------------------+
| Project / modules    | Source editor        | Types / docs      |
| Doctrine outline     |                      | Completion        |
| Squad assignments    |                      | Diagnostics       |
+----------------------+----------------------+-------------------+
| Test scenario / trace output / watches                          |
+---------------------------------------------------------------+
```

### 3.1 Editor requirements

- syntax highlighting;
- bracket and match alignment;
- inline type display;
- go-to definition;
- hover documentation;
- source diagnostics;
- type-directed completion;
- function signature help;
- format command;
- historical source view;
- diff between doctrine versions.

### 3.2 Beginner scaffolding

- editable templates;
- locked boilerplate in early missions where appropriate;
- guided blanks;
- contextual function palette;
- small runnable examples;
- one-click reset to mission default;
- warnings before destructive replacement.

## 4. Live mission UI

The live interface should not resemble a conventional RTS command bar.

Required elements:

- rendered tactical map;
- squad status strip;
- current high-level signal;
- mission objective state;
- communication status;
- program version per operative;
- event feed;
- optional overlays;
- limited signal controls.

### 4.1 Signal interaction

Map clicks can define data such as regions or extraction points.

Example:

1. Select `AdvanceTo`.
2. Paint or click a region.
3. Confirm signal scope.
4. Signal enters communication system.
5. Doctrine decides how to respond.

The UI must avoid implying immediate direct control.

## 5. Tactical overlays

Available overlays:

- vision and sensor range;
- known and uncertain contacts;
- contact confidence regions;
- line of fire;
- cover protection normals;
- intended paths;
- actual paths;
- communication links;
- target ownership;
- suppression;
- current role assignments;
- active program version;
- intention state.

Overlays should be individually toggleable and use consistent legends.

## 6. Post-mission debugger UI

Recommended layout:

```text
+---------------------------------------------------------------+
| Replay controls | Time | Filters | Compare run                |
+----------------------+----------------------+-------------------+
| Mission replay       | Causal explanation   | Source code       |
| Tactical overlays    | Event chain          | Values / watches  |
+----------------------+----------------------+-------------------+
| Timeline lanes and event markers                                |
+---------------------------------------------------------------+
```

Clicking any major event should synchronise:

- replay time;
- selected entity;
- explanation panel;
- source panel;
- timeline marker;
- relevant overlays.

## 7. Terminal visual direction

The interface should evoke a purpose-built tactical terminal rather than a generic modern code editor.

### 7.1 Font direction

- Use an original bitmap font for the shipping editor.
- Target approximately 8×12 proportions for primary source text.
- Draw inspiration from BigBlue Terminal for readability and Creep for compact telemetry.
- Use Creep-like compact glyphs only in dense telemetry or micro-panels.
- Verify all third-party font licences before bundling.
- Prefer generating or commissioning an original font to avoid ambiguity and create visual identity.

### 7.2 Required glyph distinctions

The font must clearly distinguish:

- `0`, `O`;
- `1`, `I`, `l`, `|`;
- `{`, `[`, `(`;
- `-`, `=`, `>`;
- `<`, `|`, `>`;
- `'`, `` ` ``;
- `\`, `/`.

### 7.3 Rendering

- nearest-neighbour filtering;
- integer scaling where possible;
- no fractional positioning for text;
- test at common desktop resolutions;
- offer larger scale options;
- do not rely on colour alone for syntax or diagnostics.

## 8. Visual style

Recommended direction:

- restrained monochrome or low-colour terminal panels;
- clear high-contrast tactical world;
- geometric operators and readable silhouettes;
- code-generated particles and line effects;
- minimal decorative noise;
- information-dense but spatially organised layouts.

The game world and terminal may use distinct palettes, but selected entities and trace relationships must remain visually linked.

## 9. Input model

### Keyboard

- editor shortcuts;
- compile;
- run test;
- switch panes;
- jump to diagnostic;
- toggle overlay;
- replay step;
- next/previous causal event.

### Mouse

- map inspection;
- region selection;
- timeline scrubbing;
- event selection;
- source navigation;
- drag pane resizing.

Controller support is post-MVP because the editor is central.

## 10. Accessibility

- scalable UI and font sizes;
- remappable shortcuts;
- reduced motion;
- adjustable simulation playback speed in replay;
- colour-blind-safe overlays;
- icons plus labels;
- readable compiler messages;
- optional plain-language explanation before raw trace detail;
- no essential information conveyed only through audio.

## 11. Onboarding

The first tutorial should teach through a failure:

1. Show a short mission execution.
2. Highlight an operative’s bad decision.
3. Open the causal explanation automatically.
4. Jump to one threshold in code.
5. Let the player change it.
6. Compile.
7. Rerun deterministically.
8. Show the changed branch and outcome.

Do not begin with a language lecture.

## 12. Diagnostics tone

Diagnostics should be precise and non-punitive.

Bad:

```text
Type mismatch.
```

Better:

```text
`distanceTo` expects a Position, but this expression is a Region.
Use `region.center` or select a point inside the region.
```

Warnings about tactics must be framed as possible consequences, not absolute predictions.
