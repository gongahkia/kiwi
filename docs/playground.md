# Web playground (scope stub)

A live HTML preview site for fried-apple-pie presets and personas. Hosted out of this repo; this doc defines the contract.

## Goal

A user lands on `fried-apple-pie.dev/preview` and sees a side-by-side TUI mock rendering every preset, with a persona dropdown, footer-segment toggles, and a copy-to-clipboard for the resulting `pie-ui.json`. Lowers the "should I install this" bar for visitors who don't have Pi yet.

## Data sources

The playground builds from this repo at build time:

- `themes/*.json` — every theme JSON. Use `colors.*` tokens to color the mock TUI.
- `extensions/pie-ui/config.ts` — exports `PRESETS`, `PRESET_NAMES`, `FOOTER_SEGMENTS`, `MODE_NAMES`. Parse at build time (TS → JS via `tsx`) or hand-mirror into a build script.
- `extensions/pie-ui/personas.ts` — exports `PERSONAS`, `SPINNERS`, `PRESET_DEFAULT_PERSONA`.
- `extensions/pie-ui/layers.ts` — exports `LAYERS`.

Do not duplicate constants in the playground repo. Read them from this package via a build-time copy (`npm pack` then extract, or a git submodule) so the playground never drifts.

## TUI mock structure

Roughly:

```
┌─ Header (if preset.header.enabled) ─────────────┐
│ <title>                       <subtitle>        │
├──────────────────────────────────────────────────┤
│ tool call: bash                                  │ ← rendered with current toolPendingBg
│   $ ls                                           │
│ tool result:                                     │
│   index.ts  config.ts  …                        │
├──────────────────────────────────────────────────┤
│ user message                                    │ ← userMessageBg
│ assistant message                               │
├─ Widget (if widget.enabled, aboveEditor) ───────┤
│ <lines>                                         │
├──────────────────────────────────────────────────┤
│ > editor input                                  │
├──────────────────────────────────────────────────┤
│ <spinner-frame> <verb>                          │
├─ Footer (if footer.enabled) ────────────────────┤
│ <segments joined with separator>                │
└──────────────────────────────────────────────────┘
```

Render each line with the 51-token color palette. The page should look like a screenshot but be live HTML.

## Spinner animation

JavaScript timer rotates `spinner.frames` at `spinner.intervalMs`. One animation per active preview.

## Persona dropdown

Reads `PERSONAS` and `PRESET_DEFAULT_PERSONA`. Selecting a persona updates the spinner + first verb in the mock.

## Footer toggles

Checkbox per `FOOTER_SEGMENTS` element. Conditional `when` rules (`git-repo`, `context>70`, etc.) are not evaluated client-side; show them as static badges in the preview.

## Layer composition demo

Multi-select for layers. Apply them client-side using the same merge order as `materializeConfig`: `DEFAULT → preset → layers → user`.

## Copy-to-clipboard

Button serializes the current selection to a `pie-ui.json` blob and copies. Pair with install instructions:

```sh
pi install npm:fried-apple-pie
# paste into ~/.pi/agent/pie-ui.json or .pi/pie-ui.json
```

## Hosting suggestion

- GitHub Pages on a separate repo (`fried-apple-pie-playground`) or `gh-pages` branch of this repo.
- Static site (no server). Vite + Preact or plain HTML/JS is sufficient.
- Link from the main README's hero block once shipped.

## Out of scope

- Real Pi execution (browsers can't run Pi).
- Authentication, persistence, accounts.
- Theme submission UI (out of scope; users PR theme JSONs to this repo).

## Acceptance

- Static site that renders all 16 presets side-by-side at first load.
- Persona dropdown changes spinner + verb in the active preview.
- Footer toggles add/remove segments live.
- Layer multi-select recomputes the preview using the same merge order as `materializeConfig`.
- Copy-to-clipboard outputs valid JSON that round-trips through `validateConfig` (validate via a small Node API or pre-validate in the build).
- README links to the deployed playground URL.
