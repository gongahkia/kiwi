# Fried Apple Pie UI Customization

Use this skill when the user asks to customize Pi's TUI through Fried Apple Pie presets, themes, footer/header/widget layout, or the `pie-ui.json` config.

## Rules
- Prefer the `pie_config` tool over editing config files directly.
- Read config before changing it: `pie_config` action `read`.
- Use presets for broad visual changes. Cross-agent inspired (layout + theme): `minimal`, `claude-inspired`, `opencode-inspired`, `codex-inspired`, `gemini-inspired`, `aider-inspired`, `copilot-inspired`, `cursor-inspired`, `amp-inspired`. Theme-only (minimal layout, color scheme only): `dracula`, `tokyo-night`, `catppuccin-mocha`, `catppuccin-latte`, `nord`, `gruvbox-dark`, `gruvbox-light`.
- Use the supported JSON Patch subset for targeted edits: `add`, `replace`, `remove`.
- Project config is `.pi/pie-ui.json`; global config is `~/.pi/agent/pie-ui.json`.
- Project config only applies when Pi trusts the project.
- Do not promise arbitrary panel movement; v1 supports header, footer, widgets, theme, tool expansion, thinking label, and working indicator config.
- `scope: "effective"` is read-only and should be used for dry-run validation only.
- `scope: "project"` requires project trust.
- Use `mode: "theme-only"` when another extension owns the footer or widgets.
- Use `applyMode: "clean"` to reset preset-owned config and `applyMode: "merge"` to preserve overrides.
- Persona is an orthogonal axis controlling spinner + working-message verbs. Available personas: `default`, `terse`, `arc`, `startrek`, `medieval`, `pirate`, `mlengineer`. Switch with `/pie persona <name>` or set `persona` in config. Persona does not change preset, theme, footer, or layout.

## Common Changes
- Switch preset: patch `/preset` and `/theme` together.
- Footer order: replace `/footer/segments` with any of `model`, `thinking`, `cwd`, `branch`, `status`, `context`, `tokens`, `cost`, `preset`. Each entry can be a bare string or `{ id: <segment>, when: <rule> }`. Rules: `always`, `git-repo`, `trusted-project`, `context>50`, `context>70`, `context>90`, `tokens>10k`. Example: `[{ "id": "cost", "when": "context>70" }, "branch"]`.
- Header: set `/header/enabled`, `/header/title`, and `/header/subtitle`.
- Widget: set `/widget/enabled`, `/widget/placement`, and `/widget/lines`.
- Tool display: set `/tools/expanded`.
- Compatibility mode: set `/mode` to one of `full`, `theme-only`, `footer-only`, `widgets-only`.
- Persona swap: set `/persona` to one of `default`, `terse`, `arc`, `startrek`, `medieval`, `pirate`, `mlengineer`. Affects spinner frames and initial working message.
- Use `/pie gallery` to live-preview every preset without writing to config. j/k or h/l cycles, enter keeps current preview, q/esc restores previous config.
- Use `/pie diff <preset>` to preview what a clean preset apply would change before running `/pie preset <preset>`. Optional second arg `merge` previews merge-mode apply.
- `/pie history` shows the last 10 preset switches. `/pie undo` restores the most recent previous state and pops it from history. History lives at `~/.pi/agent/pie-history.json` and is capped at 50 entries.
- `/pie import <path>` reads a local `pie-ui.json`, validates it, asks for scope and confirms before writing. URL import is not yet supported; download the JSON locally first.
- Use `/pie edit` for interactive changes and `/pie export` to inspect final merged config.
- Prefer `pie_config` actions `set_preset`, `set_footer_segments`, `toggle_compact`, and `set_theme` over raw patching for common edits.

## Validation
After every change, run `pie_config` action `validate` or use `/pie doctor`.
