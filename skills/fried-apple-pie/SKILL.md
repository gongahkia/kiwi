# Fried Apple Pie UI Customization

Use this skill when the user asks to customize Pi's TUI through Fried Apple Pie presets, themes, footer/header/widget layout, or the `pie-ui.json` config.

## Rules
- Prefer the `pie_config` tool over editing config files directly.
- Read config before changing it: `pie_config` action `read`.
- Use presets for broad visual changes. Cross-agent inspired (layout + theme): `minimal`, `claude-inspired`, `opencode-inspired`, `codex-inspired`, `gemini-inspired`, `aider-inspired`, `copilot-inspired`. Theme-only (minimal layout, color scheme only): `dracula`, `tokyo-night`, `catppuccin-mocha`, `nord`, `gruvbox-dark`.
- Use the supported JSON Patch subset for targeted edits: `add`, `replace`, `remove`.
- Project config is `.pi/pie-ui.json`; global config is `~/.pi/agent/pie-ui.json`.
- Project config only applies when Pi trusts the project.
- Do not promise arbitrary panel movement; v1 supports header, footer, widgets, theme, tool expansion, thinking label, and working indicator config.
- `scope: "effective"` is read-only and should be used for dry-run validation only.
- `scope: "project"` requires project trust.
- Use `mode: "theme-only"` when another extension owns the footer or widgets.
- Use `applyMode: "clean"` to reset preset-owned config and `applyMode: "merge"` to preserve overrides.

## Common Changes
- Switch preset: patch `/preset` and `/theme` together.
- Footer order: replace `/footer/segments` with any of `model`, `thinking`, `cwd`, `branch`, `status`, `context`, `tokens`, `cost`, `preset`.
- Header: set `/header/enabled`, `/header/title`, and `/header/subtitle`.
- Widget: set `/widget/enabled`, `/widget/placement`, and `/widget/lines`.
- Tool display: set `/tools/expanded`.
- Compatibility mode: set `/mode` to one of `full`, `theme-only`, `footer-only`, `widgets-only`.
- Use `/pie edit` for interactive changes and `/pie export` to inspect final merged config.
- Prefer `pie_config` actions `set_preset`, `set_footer_segments`, `toggle_compact`, and `set_theme` over raw patching for common edits.

## Validation
After every change, run `pie_config` action `validate` or use `/pie doctor`.
