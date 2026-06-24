# TODO

Actionable task list for `fried-apple-pie`. Self-contained: each task lists rationale, exact files/lines, implementation sketch, Pi-API references, and acceptance criteria so an independent agent can pick it up without prior context.

Conventions enforced by `CLAUDE.md`: terse, vertical-dense, in-line lowercase comments, no auto-refactor outside scope, fail fast, no `[Unverified]` labels inside code.

---

## 0. Orientation

### Repo map (under `/Users/gongahkia/Desktop/coding/projects/fried-apple-pie`)
- `package.json` — npm + Pi manifest. `pi.extensions: ["./extensions/pie-ui"]`, `pi.skills: ["./skills"]`, `pi.themes: ["./themes"]`. Peer deps: `@earendil-works/pi-coding-agent`, `@earendil-works/pi-tui`, `typebox`.
- `extensions/pie-ui/index.ts` — default-exported `(pi: ExtensionAPI) => void`. Subscribes events, registers `/pie` command and `pie_config` tool, calls `applyPie()` on `session_start`. Currently ~445 LOC.
- `extensions/pie-ui/config.ts` — constants (`PRESET_NAMES`, `FOOTER_SEGMENTS`, `MODE_NAMES`, `PRESET_THEMES`, `PRESETS`), `validateConfig`, `applyJsonPatch`, `materializeConfig`, `mergeConfig`, `applyPresetConfig`, `cloneConfig`.
- `extensions/pie-ui/paths.ts` — `loadConfig`, `readConfigFile`, `writeConfigFile`, `defaultWritePath`, `resolveWriteTarget`. Global path: `~/.pi/agent/pie-ui.json`. Project path: `<cwd>/.pi/pie-ui.json` (requires `ctx.isProjectTrusted()`).
- `extensions/pie-ui/render.ts` — `createFooter`, `createHeader`, `widgetLines`, picker overlays (`PresetPicker`, `EditPicker`, `FooterSegmentPicker`, `TextPanel`), footer segment renderer switch (`renderSegment` at `render.ts:315`).
- `themes/*.json` — 5 themes; every theme must contain 51 color tokens (canonical list at `tests/config.test.ts:12-64`).
- `schema/pie-ui.schema.json` — JSON Schema. Enums MUST stay in sync with `config.ts` (enforced by test at `tests/config.test.ts:134-145`).
- `skills/fried-apple-pie/SKILL.md` — agent-facing instructions; update when commands/tool actions change.
- `tests/config.test.ts` — `node:test` runner via tsx. 14 tests today.

### Build / verify
- `npm run typecheck` — `tsc --noEmit`.
- `npm test` — `node --import tsx --test tests/*.test.ts`.
- `npm run verify` — both.
- `npm run smoke:pi` — `pi -e . --offline --no-context-files --list-models >/dev/null`.
- `npm run assets:build` — regenerate gallery PNG/GIF (uses macOS `sips` + ImageMagick `magick`).

### Pi API inventory (canonical: `https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/extensions.md`)

**Used today** (grep `pi.on`, `pi.register*`, `ctx.ui.` in `extensions/pie-ui/`):
- Events: `resources_discover`, `session_start`, `agent_start`, `agent_end`, `model_select`, `thinking_level_select`, `message_end`.
- `pi.registerCommand("pie", …)`, `pi.registerTool({ name: "pie_config", … })`, `pi.getCommands`, `pi.getThinkingLevel`, `pi.exec`, `pi.appendEntry`.
- Built-in tool overrides for `bash`, `edit`, `read`, `grep` via `renderCall`/`renderResult`; execution/schemas cloned from Pi's own tool definitions.
- `ctx.ui`: `setTheme`, `setToolsExpanded`, `setHiddenThinkingLabel`, `setWorkingVisible`, `setWorkingMessage`, `setWorkingIndicator`, `setWidget`, `setHeader`, `setFooter`, `notify`, `select`, `input`, `confirm`, `getAllThemes`, `custom`, `editor`, `addAutocompleteProvider`.

**Not yet used** (all verified present in extensions.md):
- `pi.registerMessageRenderer(customType, (message, opts, theme) => Component)` — per-customType TUI rendering.
- `pi.registerShortcut(shortcut, { description, handler })` — chord registration.
- `pi.registerFlag(name, { description, type, default })` — CLI flag.
- `pi.sendMessage(message, options?)` — inject custom-type message; `delivery` ∈ `"steer" | "followUp" | "nextTurn"`; `triggerTurn?: boolean`.
- `pi.events` — inter-extension event bus.
- `pi.setSessionName`, `pi.setLabel`.
- `ctx.ui.setStatus(key, text?)`, `ctx.ui.setTitle`, `ctx.ui.setEditorComponent`, `ctx.ui.pasteToEditor`, `ctx.ui.getEditorText`/`setEditorText`.
- Built-in tool overrides for `write`, `find`, `ls` (read/bash/edit/grep now have Fried Apple Pie renderers).
- `highlightCode`, `getLanguageFromPath`, `keyHint`, `keyText`, `truncateHead`, `truncateTail` utilities from `@earendil-works/pi-tui`.
- Events not subscribed: `project_trust`, `turn_end`, `tool_execution_start/update/end`, `tool_call`, `tool_result`, `input`, `user_bash`, `session_before_compact`, `before_provider_request`, `after_provider_response`, `session_before_switch/fork/tree`.

### Coexistence targets (doctor must detect)
- `pi-powerline-footer` — owns footer + welcome overlay.
- `pi-tool-display` — owns tool rendering.
- `amp-themes` / `@smoose/pi-themes` / `pi-ansi-themes` / `pi-coding-agent-catppuccin` — own theme.
- `tintinweb/pi-subagents` — fixed Claude Code aesthetic bundled with sub-agent runner.

### Verify-before-promise
Before relying on any newly-used Pi API call (especially `registerMessageRenderer`, `before_agent_start` payload shape, built-in tool override slots, `pi.events`, `pi.exec`), boot Pi locally with `npm run smoke:pi` and `pi -e .` to confirm runtime shape. Docs are the source of truth but field names occasionally drift.

---

## 1. Tasks

Priority key: **P0** viral lift (high impact, low risk) · **P1** depth · **P2** stickiness · **P3** platform.

Each task is self-contained. Dependencies noted explicitly.

---

### P0-01 follow-ups (per-preset screenshots)

README rewrite landed (comparison table, migration block, persona section, agent tool section, compat list with known co-existence pairings). Still pending: per-preset screenshot grid — depends on P0-02 (`/pie capture` via vhs) producing assets/preview-<preset>.gif|png for each of the 12 presets. Once P0-02 lands, add a "Gallery" section with a grid of preview images and update the first-screen hero from the current static GIF.

---

### P3-23 — Preset SDK for third-party packages

- [ ] Export `defineFriedApplePiePreset(...)` so others can publish presets that depend on this package.

**Files:** new `extensions/pie-ui/sdk.ts`, `package.json` `exports` map.

**Sketch:**
```ts
export type PresetDefinition = {
  name: string;
  theme: ThemeFile;            // 51-token JSON shape
  config: Partial<PieConfig>;
  banner?: string[];
  persona?: { spinner: string; verbs: string };
};
export function defineFriedApplePiePreset(spec: PresetDefinition): PresetDefinition { return spec; }
```
Third-party packages depend on `fried-apple-pie`, export a default `PresetDefinition`, Pi discovers via `pi.themes` and `pi.extensions` (host extension can scan loaded extensions for `__friedApplePiePreset` markers).

**Refs:** lualine-themes ecosystem for ergonomic precedent.

**Acceptance:** README "Authoring presets" section; example package stub in `examples/`.

---

### P3-24 — Theme-extraction CLI `npx fap capture-terminal`

- [ ] Read terminal OSC color responses, emit a Pi-compatible 51-token theme JSON.

**Files:** new `bin/fap-capture-terminal.ts`, `package.json` `bin: { fap: "./bin/fap-capture-terminal.ts" }` (or compiled JS).

**Sketch:**
- Use OSC 4 queries (`\x1b]4;<idx>;?\x07`) for ANSI 0-15. Read response from stdin within timeout.
- Map ANSI → 51 tokens via heuristic similar to `leblancfg/pi-ansi-themes`:
  - ANSI 1=error, 2=success, 3=warning, 4=accent2, 5=accent, 6=accent2, 7=text, 8=dim.
  - Backgrounds (`*Bg`) from terminal default bg.
- Write `themes/<name>.json` with `{ $schema, name, vars, colors }`.

**Refs:** leblancfg/pi-ansi-themes for ANSI-mapping precedent: https://github.com/leblancfg/pi-ansi-themes.

**Acceptance:** `npx fap capture-terminal --name my-theme` writes a valid 51-token theme. `npm test` passes against generated files.

---

### P3-26 — Telemetry-free opt-in stats

- [ ] Anonymized POST to registry when user opts in. Defaults off.

**Files:** new `extensions/pie-ui/stats.ts`. Config extension. Doctor reporting.

**Sketch:** opt-in flag `analytics.enabled: true`. POST `{ preset, persona, layers, hashedInstallId: sha256(homedir + machineId).slice(0,16) }` once per session. No IP capture beyond what the HTTP server logs.

**Acceptance:** opt-out by default; flag toggleable via `/pie edit`; doctor reports state.

---

## 2. Cross-cutting hygiene (always)

- [ ] **CC-01** Update `skills/fried-apple-pie/SKILL.md` whenever a new command/subcommand/tool action is added so the Pi agent can drive it.
- [ ] **CC-02** Keep `schema/pie-ui.schema.json` enums in sync with `extensions/pie-ui/config.ts` constants. Test at `tests/config.test.ts:134-145` enforces.
- [ ] **CC-03** All themes must include 51 tokens (canonical list `tests/config.test.ts:12-64`). Tests enforce token completeness (`:119-125`) and preset↔theme mapping (`:112-117`).
- [ ] **CC-04** Verify each new Pi API call with `npm run smoke:pi` and a manual `pi -e .` run before promising it. Docs are authoritative but field shapes occasionally drift.
- [ ] **CC-05** Before adding any new event subscription, confirm event payload shape in a smoke test — extensions.md lists handlers but not always every field name.

---

## 3. Comparative reference (for prioritization context)

| Surface | fried-apple-pie | tweakcc (CC) | amp-themes (Pi) | pi-powerline-footer | ccstatusline (CC) | lualine (nvim) | opencode |
|---|---|---|---|---|---|---|---|
| Multi-preset switch | **16** | — | — | — | scripted | themes | themes |
| Tool rendering | expand-only | — | pills/cards | — | — | n/a | — |
| Spinners | **10 vendored** | **70+** | — | — | — | n/a | n/a |
| Thinking verbs | **7 personas** | **custom lib** | — | AI "vibes" | — | n/a | n/a |
| Boot/welcome ASCII | startup banner | sign-in ASCII | — | **branded splash + stats** | — | winbar | — |
| User-msg styling | theme | **per element** | compact | — | n/a | n/a | n/a |
| Markdown styling | — | **yes** | partial | — | n/a | n/a | n/a |
| Keybinds registered | — | — | — | **alt+s, ctrl+shift+b** | — | n/a | yes |
| Conditional segments | **7 rules** | n/a | n/a | context-warn | flexible | richest | — |
| Sticky bash | — | — | — | yes | — | n/a | n/a |
| Recent-prompts overlay | — | — | — | yes (50) | — | n/a | n/a |
| Persona / output-style | — | — | — | working-vibes | — | n/a | n/a |
| Capture / share | bundle | — | — | — | — | n/a | n/a |
| Doctor / conflict check | **unique** | — | — | — | — | n/a | — |
| Agent-readable config | **unique** | — | — | — | — | n/a | — |
| JSON Patch agent API | **unique** | — | — | — | — | n/a | — |
| Trust scope | global+project | — | — | — | yes | n/a | yes |
| Tests shipped | **yes** | partial | — | — | — | yes | — |

---

## 4. Reference index

- Pi extensions canonical: https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/extensions.md
- Pi keybindings: https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/keybindings.md
- Pi themes (51-token schema): https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/themes.md
- Pi packages: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md
- Pi catalog: https://pi.dev/packages
- vhs (CLI recorder): https://github.com/charmbracelet/vhs
- vhs-action (CI): https://github.com/charmbracelet/vhs-action
- cli-spinners (MIT, vendorable): https://github.com/sindresorhus/cli-spinners
- tweakcc (Claude Code customization parity bar): https://github.com/Piebald-AI/tweakcc
- pi-powerline-footer (Pi feature parity reference): https://github.com/nicobailon/pi-powerline-footer
- amp-themes (Pi tool-rendering precedent): https://pi.dev/packages/amp-themes
- tintinweb/pi-subagents (collision-watch target): https://github.com/tintinweb/pi-subagents
- Claude Code statusline: https://code.claude.com/docs/en/statusline
- ccstatusline: https://github.com/sirmalloc/ccstatusline
- lualine.nvim: https://github.com/nvim-lualine/lualine.nvim
- OpenCode config: https://opencode.ai/docs/config/
- OpenCode themes: https://opencode.ai/docs/themes/
- leblancfg/pi-ansi-themes (ANSI-only theme pattern): https://github.com/leblancfg/pi-ansi-themes
- otahontas/pi-coding-agent-catppuccin: https://github.com/otahontas/pi-coding-agent-catppuccin
- catppuccin palette: https://github.com/catppuccin/catppuccin
- tokyo-night palette: https://github.com/folke/tokyonight.nvim
- nord palette: https://www.nordtheme.com
- gruvbox palette: https://github.com/morhetz/gruvbox
- dracula: https://draculatheme.com

---

## 5. Order-of-operations recommendation

Suggested sequence to balance viral demo and depth without half-finished work:

1. ~~P0-04 (12+ presets)~~ — done.
2. ~~P0-02 (`/pie capture` + vhs)~~ — done.
3. ~~P0-03 (`/pie gallery`)~~ — done.
4. ~~P0-01 (README rewrite)~~ — done. Per-preset screenshot grid still pending P0-02.
5. ~~P0-05 (personas)~~ — done.
6. ~~P0-06 (boot ASCII)~~ — done.
7. ~~P1-08 (keybindings)~~ — done.
8. ~~P1-12 (launch preset flag)~~ — done.
9. ~~P1-15 (persona prompt suffix)~~ — done.
10. ~~P1-11 (`/pie share`)~~ — done.
11. ~~P0-07 (per-preset tool rendering)~~ — done.
12. P2 / P3 as bandwidth allows.

[Inference] This sequence ships visible artifacts every 1–2 days for the first week, which matches the viral-first signal from the project intent.
