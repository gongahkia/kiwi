# AGENTS.md

Cross-agent guide for `fried-apple-pie`. If you are a coding agent (Pi, Claude Code, Codex, Aider, Gemini CLI, OpenCode, etc.) operating in a Pi project that has `fried-apple-pie` installed, follow this guide before assuming UI defaults.

## Project purpose

`fried-apple-pie` is a Pi UI customization package: 16 presets, 7 personas, agent-editable config. The Pi agent inside the session has a registered tool named `pie_config` and a `/pie` slash command. Other agents reaching this project via MCP, file-system access, or shell should prefer those entry points over editing config files directly.

## Tool: `pie_config`

Registered as a Pi tool when the extension is loaded. Use this rather than reading or writing `pie-ui.json` by hand.

### Actions

- `read` — return `{ paths, projectTrusted, globalConfig, projectConfig, effective, validation, readErrors }`. Always call this before changing config.
- `list_presets` — return `Record<PresetName, PieConfig>` of bundled preset definitions.
- `validate` — validate a candidate config or the current effective one. Accepts `config?: PieConfig` and `strict?: boolean`.
- `patch` — apply a JSON Patch subset to a scope. `patch: Array<{ op: "add" | "replace" | "remove", path: string, value?: unknown }>`. Use `dryRun: true` to preview without writing.
- `apply` — write a full `config` to a scope. `dryRun: true` validates without writing.
- `set_preset` — convenience: writes `{ preset, theme }`. Accepts `applyMode: "clean" | "merge"` (default `merge`).
- `set_footer_segments` — convenience: writes `footer.segments`.
- `toggle_compact` — flip `compact`.
- `set_theme` — set `theme` by name.

### Scopes

- `global` — `~/.pi/agent/pie-ui.json`. Always writable.
- `project` — `<cwd>/.pi/pie-ui.json`. Requires `ctx.isProjectTrusted()`; reject without trust.
- `effective` — read-only merged view. `apply`/`patch` against this scope require `dryRun: true`.

### Common workflows

Switch preset cleanly:

```json
{ "action": "set_preset", "preset": "codex-inspired", "applyMode": "clean", "scope": "project" }
```

Patch a single key:

```json
{
  "action": "patch",
  "scope": "project",
  "patch": [{ "op": "replace", "path": "/footer/segments", "value": ["model", "branch", "context", "tokens"] }]
}
```

Preview before applying:

```json
{ "action": "patch", "scope": "effective", "dryRun": true, "patch": [...] }
```

Validate strictly (rejects unknown keys):

```json
{ "action": "validate", "strict": true }
```

## Slash commands

If you operate the TUI directly:

```txt
/pie                 open preset picker
/pie preset <name> [clean|merge]
/pie mode <full|theme-only|footer-only|widgets-only>
/pie persona <name>  swap spinner + verbs (orthogonal to preset)
/pie gallery         live preview every preset (no writes)
/pie diff <name>     preview keys that would change
/pie history         show preset switch history
/pie undo            restore previous preset config
/pie import <path>   import a local pie-ui.json
/pie capture         render active preset tape via vhs
/pie edit            interactive editor
/pie welcome         active config + command list
/pie show            global + project + effective
/pie export          effective only
/pie doctor [strict] validate + detect conflicts
/pie reset           return to minimal
```

## Constants worth knowing

- Presets (16): `minimal`, `claude-inspired`, `opencode-inspired`, `codex-inspired`, `gemini-inspired`, `aider-inspired`, `copilot-inspired`, `cursor-inspired`, `amp-inspired`, `dracula`, `tokyo-night`, `catppuccin-mocha`, `catppuccin-latte`, `nord`, `gruvbox-dark`, `gruvbox-light`.
- Personas (7): `default`, `terse`, `arc`, `startrek`, `medieval`, `pirate`, `mlengineer`. Each pairs a spinner with a verb pack; persona is orthogonal to preset.
- Footer segments: `model`, `thinking`, `cwd`, `branch`, `status`, `context`, `tokens`, `cost`, `preset`.
- Modes (what fried-apple-pie owns): `full`, `theme-only`, `footer-only`, `widgets-only`, `status-only`.
- Apply modes: `clean` resets preset-owned keys, `merge` preserves overrides.

## Coexistence with other Pi packages

`/pie doctor` detects known conflicts. When `pi-powerline-footer`, `pi-tool-display`, or another themed footer/widget owner is loaded, set a non-`full` mode rather than forcing one side off. See `README.md#compatibility-with-other-pi-packages`.

## Files an agent should know

- `schema/pie-ui.schema.json` — JSON Schema for editor autocomplete. Reference with `{ "$schema": "./schema/pie-ui.schema.json", ... }`.
- `skills/fried-apple-pie/SKILL.md` — concise rules for Pi's own agent.
- `extensions/pie-ui/config.ts` — source of truth for `PRESET_NAMES`, `PRESET_THEMES`, `PRESETS`, `FOOTER_SEGMENTS`, `MODE_NAMES`, validation, JSON Patch.
- `extensions/pie-ui/personas.ts` — `SPINNERS`, `PERSONAS`, `PRESET_DEFAULT_PERSONA`.
- `extensions/pie-ui/banners.ts` — startup ASCII banners for every preset.
- `themes/*.json` — 16 themes, 51 color tokens each.

## Behaviors to avoid

- Do not hand-edit `pie-ui.json` if `pie_config` is reachable.
- Do not assume `project` scope is writable — check `projectTrusted` from `read` first.
- Do not promise arbitrary panel movement; only surfaces listed under "Constants" exist in v1.
- Do not copy banner ASCII or theme tokens verbatim from upstream agent repos when authoring new presets; produce original interpretations.
