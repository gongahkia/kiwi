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
- `pi.registerCommand("pie", …)`, `pi.registerTool({ name: "pie_config", … })`, `pi.getCommands`, `pi.getThinkingLevel`.
- `ctx.ui`: `setTheme`, `setToolsExpanded`, `setHiddenThinkingLabel`, `setWorkingVisible`, `setWorkingMessage`, `setWorkingIndicator`, `setWidget`, `setHeader`, `setFooter`, `notify`, `select`, `input`, `confirm`, `getAllThemes`, `custom`.

**Not yet used** (all verified present in extensions.md):
- `pi.registerMessageRenderer(customType, (message, opts, theme) => Component)` — per-customType TUI rendering.
- `pi.registerShortcut(shortcut, { description, handler })` — chord registration.
- `pi.registerFlag(name, { description, type, default })` — CLI flag.
- `pi.sendMessage(message, options?)` — inject custom-type message; `delivery` ∈ `"steer" | "followUp" | "nextTurn"`; `triggerTurn?: boolean`.
- `pi.appendEntry(customType, data?)` — persist state outside LLM context.
- `pi.events` — inter-extension event bus.
- `pi.setSessionName`, `pi.setLabel`.
- `pi.exec(command, args, options?)` — shell exec with signal + timeout.
- `ctx.ui.setStatus(key, text?)`, `ctx.ui.setTitle`, `ctx.ui.editor`, `ctx.ui.addAutocompleteProvider`, `ctx.ui.setEditorComponent`, `ctx.ui.pasteToEditor`, `ctx.ui.getEditorText`/`setEditorText`.
- Tool definition `renderCall(args, theme) => Component`, `renderResult(result, opts, theme) => Component`, `renderShell: "self"`.
- Built-in tool overrides (`read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`). Renderers and `execute` are independent — omitting either preserves built-in for that slot.
- `highlightCode`, `getLanguageFromPath`, `keyHint`, `keyText`, `truncateHead`, `truncateTail` utilities from `@earendil-works/pi-tui`.
- Events not subscribed: `project_trust`, `before_agent_start`, `turn_start`, `turn_end`, `tool_execution_start/update/end`, `tool_call`, `tool_result`, `input`, `user_bash`, `session_before_compact`, `session_compact`, `before_provider_request`, `after_provider_response`, `session_before_switch/fork/tree`.

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

### P0-02 follow-ups (doctor PATH check)

P0-02 shipped: 16 tapes in `assets/tapes/`, `scripts/gen-tapes.sh` regenerates, `scripts/capture.sh` runs every tape, `assets:tapes` / `assets:capture` npm scripts, `/pie capture` subcommand using `pi.exec` with optional-chain fallback. Tape sync test confirms every preset has a matching tape. Still pending: doctor active PATH probe for `vhs`/`ttyd`/`ffmpeg` — `pi.exec` is needed to probe at runtime, same verification risk as `/pie capture` itself. Future agent: in `doctorLines`, call `pi.exec?.("which", ["vhs"])` (or use `node:child_process` defensively) and report missing tools.

---


### P0-05 follow-ups (initial-message rotation)

P0-05 main goal hit: 10 vendored spinners, 7 personas (`default`, `terse`, `arc`, `startrek`, `medieval`, `pirate`, `mlengineer`), per-preset default-persona binding, `/pie persona <name>` subcommand, persona validation, schema field, 3 new tests. Still deferred: per-turn verb rotation (cycles through `PERSONAS[name].verbs` on each `turn_start` event). Implementation note for future agent: subscribe to `pi.on("turn_start", …)`, maintain a counter in `RenderState`, call `ctx.ui.setWorkingMessage(verbs[counter % verbs.length])`. Risk: confirm `turn_start` event payload shape and rotation timing via `npm run smoke:pi` before relying.

---

### P0-06 — Boot ASCII art per preset (`pi.sendMessage` + `registerMessageRenderer`)

- [ ] Add ASCII banner per preset; deliver as a custom-type message at `session_start`.

**Why:** branded welcome moment. pi-powerline-footer's splash is a star magnet. Original art only — no copy from claude/codex/gemini repos.

**Files:**
- new `extensions/pie-ui/banners.ts` — `BANNERS: Record<PresetName, string[]>`.
- `extensions/pie-ui/index.ts` — register renderer; send message in `session_start` handler at `index.ts:68-70`.
- `extensions/pie-ui/config.ts` — new `welcome?: { enabled?: boolean; banner?: string[] }` field.
- `schema/pie-ui.schema.json` — `welcome` block.

**Sketch:**
```ts
pi.registerMessageRenderer("pie:welcome", (message, _opts, theme) => {
  // return a Component (use truncateToWidth + theme.fg per render.ts patterns)
  return { invalidate() {}, render(width) { return (message.details as { lines: string[] }).lines.map(l => theme.fg("accent", l)); } };
});
pi.on("session_start", (event, ctx) => {
  applyPie(ctx, pi, state);
  if (event.reason !== "startup") return; // skip on reload/fork to avoid noise
  const cfg = loadConfig(ctx.cwd, ctx.isProjectTrusted()).effective;
  if (cfg.welcome?.enabled === false) return;
  const lines = cfg.welcome?.banner ?? BANNERS[cfg.preset ?? "minimal"];
  pi.sendMessage({ customType: "pie:welcome", content: "", display: true, details: { lines } });
});
```

`session_start` `event.reason` values: `"startup" | "reload" | "new" | "resume" | "fork"` per extensions.md.

**Refs:** `registerMessageRenderer` signature per extensions.md: `(message, opts, theme) => Component`. Banner shape similar to existing `widgetLines` at `render.ts:61-66`.

**Acceptance:** banner shows at first session start; suppressed on reload/fork; config flag disables. Doctor warns if another extension owns a welcome overlay (detect `pi-powerline-footer` by command presence).

---

### P0-07 — Per-preset tool rendering via `renderCall`/`renderResult`

- [ ] Override built-in `bash`, `edit`, `read`, `grep` renderers with preset-driven styles. Ship one style end-to-end before templating the rest.

**Why:** single largest visual lift. Differentiates from amp-themes (one style) and pi-subagents (fixed Claude style) by switching style per preset. Highest engineering cost; ship one style first to de-risk.

**Files:**
- new `extensions/pie-ui/tool-renderers.ts` — style implementations.
- `extensions/pie-ui/index.ts` — register tool overrides in addition to `pie_config`.
- `extensions/pie-ui/config.ts` — extend `tools?: { expanded?: boolean; renderStyle?: "pill" | "card" | "dense" | "minimal" }`.
- `extensions/pie-ui/render.ts` — shared helpers if needed.
- `schema/pie-ui.schema.json` — extend `tools` properties.

**Sketch:**
```ts
// tool-renderers.ts
export type ToolRenderStyle = "pill" | "card" | "dense" | "minimal";
import type { Component } from "@earendil-works/pi-tui";

export function renderToolCall(style: ToolRenderStyle, name: string, args: unknown, theme: ThemeLike): Component { /* … */ }
export function renderToolResult(style: ToolRenderStyle, name: string, result: { content: { type: "text"; text: string }[]; details?: unknown }, opts: { expanded: boolean }, theme: ThemeLike): Component { /* … */ }
```
Built-in override (extensions.md confirms renderers and `execute` are independent — omit `execute` to keep built-in):
```ts
for (const name of ["bash", "edit", "read", "grep"] as const) {
  pi.registerTool({
    name,
    label: name,
    description: "", // built-in
    parameters: Type.Any(),
    renderCall:   (args, theme)        => renderToolCall  (currentStyle(), name, args, theme),
    renderResult: (result, opts, theme) => renderToolResult(currentStyle(), name, result, opts, theme),
    // execute omitted -> built-in execute preserved
  });
}
```

`currentStyle()` reads cached `applyPie` config — store the last-applied style in module-scope state (similar to `RenderState`).

Build one style at a time:
1. Start with `dense` for `codex-inspired` (single-row header, inline diff).
2. Add `pill` for `claude-inspired` (compact pill chips).
3. Add `card` for `gemini-inspired` (bordered card with metadata).
4. Add `minimal` for `minimal` and `aider-inspired`.

**Refs:**
- extensions.md §"Built-in Tool Override Details" — confirms slots independent.
- `truncateHead`, `truncateTail`, `highlightCode`, `getLanguageFromPath`, `keyHint` from `@earendil-works/pi-tui`.
- amp-themes for "Amp-style tool rendering" precedent (do not copy code).

**Risks:** built-in tool override semantics need empirical verification — register only renderers (no `execute`) and confirm `bash`/`edit`/`read`/`grep` still run normally via `npm run smoke:pi` + manual `pi -e .` smoke. If override mode silently disables execute, fall back to wrapping output by listening on `tool_result` event and rendering via `setWidget` (less elegant).

**Acceptance:** switching presets visibly changes tool-call rendering. 4 styles ship. Each preset declares its style. Built-in tool behavior (success/error/output) unchanged.

---

### P1-08 — Keybindings via `pi.registerShortcut` with leader prefix

- [ ] Register `ctrl+p` leader chord plus `p/g/s/e/d/c` follow-ups. Document rebind path.

**Why:** parity with `pi-powerline-footer` (alt+s, ctrl+shift+b). Zero shortcuts today.

**Files:** `extensions/pie-ui/index.ts` (add `pi.registerShortcut` block alongside `registerCommand`). README + SKILL.md updates.

**Sketch:**
```ts
pi.registerShortcut("ctrl+p p", { description: "Fried Apple Pie: preset picker",   handler: async (ctx) => { /* call pickPreset + writePreset */ } });
pi.registerShortcut("ctrl+p g", { description: "Fried Apple Pie: gallery cycle",   handler: async (ctx) => { /* P0-03 entry */ } });
pi.registerShortcut("ctrl+p s", { description: "Fried Apple Pie: footer segments", handler: async (ctx) => { /* pickFooterSegments */ } });
pi.registerShortcut("ctrl+p e", { description: "Fried Apple Pie: edit",            handler: async (ctx) => { /* editConfig */ } });
pi.registerShortcut("ctrl+p d", { description: "Fried Apple Pie: doctor",          handler: async (ctx) => { /* doctorLines panel */ } });
pi.registerShortcut("ctrl+p c", { description: "Fried Apple Pie: capture",         handler: async (ctx) => { /* P0-02 entry */ } });
```

Rebind path (document in README): `~/.pi/agent/keybindings.json` — per keybindings.md https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/keybindings.md. After editing, run `/reload` in Pi.

**Refs:** keybindings.md.

**Acceptance:** all six shortcuts work; README documents rebind; doctor lists active chords.

---

### P1-11 — `/pie share` to static registry

- [ ] Subcommand that bundles current effective config + screenshot into a shareable payload.

**Why:** community flywheel. Users export their config, others install via slug.

**Files:** `extensions/pie-ui/index.ts` (subcommand), new `docs/registry.md` describing protocol, optional `scripts/share.sh`.

**Sketch (MVP, server-stub):**
- `/pie share` writes `pie-ui.json` + latest screenshot to `assets/share/<timestamp>/`.
- `pi.exec("curl", ["-fsSL", "-X", "POST", "https://fried-apple-pie.dev/api/share", "-d@-"], { input: payload })` — server returns slug; if unreachable, fall back to printing local files and a `gh gist create` command suggestion.
- Doc `docs/registry.md` defines payload schema (`{ config, screenshotPath, author, version, timestamp }`) and `pi install fap:<slug>` resolution behaviour for a future Pi-side resolver.

**Refs:** `pi.exec` per extensions.md. `pi install` resolves `npm:` and git URLs per packages.md; custom protocols would need Pi-side hook.

**Acceptance:** command works offline (prints fallback). Server-side optional. `docs/registry.md` documents protocol.

---

### P1-12 — CLI flag `pi --pie-preset=<name>`

- [ ] Register a flag for one-shot launches into a preset without writing config.

**Why:** blog tutorials and demo videos.

**Files:** `extensions/pie-ui/index.ts`.

**Sketch:**
```ts
pi.registerFlag("pie-preset", { description: "Apply Fried Apple Pie preset on launch", type: "string", default: "" });

pi.on("session_start", (_event, ctx) => {
  const flag = pi.getFlag?.("pie-preset"); // verify retrieval API name with smoke test
  if (flag && PRESET_NAMES.includes(flag as PresetName)) {
    state.transientPreset = flag as PresetName;
  }
  applyPie(ctx, pi, state);
});
```
Transient preset: skip write to `pie-ui.json`; pass as override into `applyPie` (see P0-03 `applyPieOverride`).

**Refs:** extensions.md `pi.registerFlag` — verify exact retrieval API (`pi.getFlag` vs flag-as-arg) with smoke test before relying on it.

**Acceptance:** `pi --pie-preset codex-inspired -e .` boots into preset; nothing written to disk.

---

### P1-15 — Persona system prompt suffix (orthogonal axis)

Depends on P0-05.

- [ ] Each persona may carry a `systemPromptSuffix`. Applied via `before_agent_start`.

**Why:** Claude Code `/output-style` proved demand for instant personality changes that affect agent tone.

**Files:** `extensions/pie-ui/personas.ts` (extend `VERB_PACKS` shape), `extensions/pie-ui/index.ts` (subscribe `before_agent_start`).

**Sketch:**
```ts
pi.on("before_agent_start", (event, ctx) => {
  const persona = currentVerbPack();
  if (!persona?.systemPromptSuffix) return;
  event.messages.unshift({ role: "system", content: persona.systemPromptSuffix });
});
```
Verify `event.messages` field name + mutability via smoke test before relying. extensions.md describes the event as "inject messages, modify system prompt" but exact field shape requires runtime confirmation.

**Acceptance:** `/pie persona terse` shortens verbs + adds "respond tersely, omit preamble" suffix; `/pie persona vibes-startrek` only changes verbs.

---

### P2-17 follow-ups (Pi event-bus integration)

P2-17 main goal hit: `/pie history` and `/pie undo` ship; preset writes record `{ ts, scope, path, previous, next }` at `~/.pi/agent/pie-history.json`; rolling 50-entry cap; 3 new tests. Storage uses a plain JSON file instead of `pi.appendEntry` to avoid runtime-shape verification. Future agent: optionally also call `pi.appendEntry?.("pie:history", entry)` so other extensions on the same Pi session bus can react.

---

### P2-18 follow-ups (URL import)

P2-18 file import shipped: validates, asks for scope, confirms, writes, records to history. URL import deferred until `pi.exec` runtime shape is verified — current behavior is to notify and ask the user to download locally first. Future agent should add `pi.exec?.("curl", ["-fsSL", url])` branch (with try/catch on absent `pi.exec`) above the file path.

---

### P2-19 — Inline `ctx.ui.editor` config edit + autocomplete

- [ ] `/pie edit-json` opens multi-line editor seeded with current effective config; autocomplete for known keys/enums.

**Files:** `extensions/pie-ui/index.ts` (subcommand + `addAutocompleteProvider`).

**Sketch:**
```ts
const text = await ctx.ui.editor("Fried Apple Pie config", JSON.stringify(loaded.effective, null, 2));
if (!text) return;
const parsed = JSON.parse(text);
const v = validateConfig(parsed);
if (!v.valid) { ctx.ui.notify(`Invalid: ${v.errors[0]}`, "error"); return; }
const target = await chooseWriteTarget(ctx);
if (target) { writeConfigFile(target.path, parsed); applyPie(ctx, pi, state); }
```
Autocomplete provider matches when text contains `pie-ui.json`-relevant patterns (`"preset":`, `"mode":`, etc.) and returns enums from `PRESET_NAMES`, `MODE_NAMES`, `FOOTER_SEGMENTS`.

**Refs:** `ctx.ui.editor`, `ctx.ui.addAutocompleteProvider` per extensions.md.

**Acceptance:** editing in TUI, saving applies live; autocomplete suggests enum values.

---

### P2-22 — AGENTS.md for cross-agent friendliness

- [ ] Blocked on `.gitignore`: file `AGENTS.md` is already drafted at repo root locally (full content covers project purpose, `pie_config` tool actions, scopes/trust, slash commands, constants, coexistence pointers, behaviors to avoid). `.gitignore` lists `AGENTS.md` so `git add` refuses without `-f`. Decision needed from repo owner: (a) remove `AGENTS.md` from `.gitignore` and commit (recommended — Pi catalog and Claude marketplaces auto-index AGENTS.md and the file is generic, not personal), or (b) keep ignored if there is a personal/local reason. If (a), run `sed -i '' '/^AGENTS\.md$/d' .gitignore && git add AGENTS.md .gitignore && git commit`.

**Files:** `AGENTS.md` (already written, untracked).

**Acceptance unmet:** file exists locally but not in tracked tree.

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
| Boot/welcome ASCII | title+subtitle | sign-in ASCII | — | **branded splash + stats** | — | winbar | — |
| User-msg styling | theme | **per element** | compact | — | n/a | n/a | n/a |
| Markdown styling | — | **yes** | partial | — | n/a | n/a | n/a |
| Keybinds registered | — | — | — | **alt+s, ctrl+shift+b** | — | n/a | yes |
| Conditional segments | **7 rules** | n/a | n/a | context-warn | flexible | richest | — |
| Sticky bash | — | — | — | yes | — | n/a | n/a |
| Recent-prompts overlay | — | — | — | yes (50) | — | n/a | n/a |
| Persona / output-style | — | — | — | working-vibes | — | n/a | n/a |
| Capture / share | — | — | — | — | — | n/a | n/a |
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
6. P0-06 (boot ASCII) — needs `registerMessageRenderer`; lower complexity.
7. P0-07 (per-preset tool rendering) — biggest engineering cost; ship one style end-to-end first (codex-inspired, dense).
8. P1-08 → P1-15 in parallel.
9. P2 / P3 as bandwidth allows.

[Inference] This sequence ships visible artifacts every 1–2 days for the first week, which matches the viral-first signal from the project intent.
