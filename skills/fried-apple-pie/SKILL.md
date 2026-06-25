---
name: fried-apple-pie
description: Customize Pi's TUI through Fried Apple Pie presets, themes, footer/header/widget layout, personas, and pie-ui.json config.
---

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
- Use `mode: "status-only"` when another extension owns header/footer/widget but you still want a small `setStatus` surface showing preset and context usage.
- Opt out of automatic context warnings (70% info, 90% warning) by setting `notifications.contextWarnings: false`.
- Analytics defaults off. Enable only with `analytics.enabled: true` and an explicit `analytics.endpoint`; payload contains preset, persona, layers, and a hashed install id.
- Compose layered decorations via `layers: ["theme:gemini", "footer:powerline", "persona:terse"]`. Layers apply between preset and user config (preset → layers in order → user overrides). Categories: `theme:*`, `footer:*`, `welcome:*`, `persona:*`, `compact:*`.
- Use `applyMode: "clean"` to reset preset-owned config and `applyMode: "merge"` to preserve overrides.
- Persona is an orthogonal axis controlling spinner + working-message verbs, with optional per-turn system prompt suffixes. Available personas: `default`, `terse`, `arc`, `startrek`, `medieval`, `pirate`, `mlengineer`. Switch with `/pie persona <name>` or set `persona` in config. `terse` appends a terse response suffix. Persona does not change preset, theme, footer, or layout.

## Common Changes
- Switch preset: patch `/preset` and `/theme` together.
- Footer order: replace `/footer/segments` with any of `model`, `thinking`, `cwd`, `branch`, `status`, `context`, `tokens`, `cost`, `preset`. Each entry can be a bare string or `{ id: <segment>, when: <rule> }`. Rules: `always`, `git-repo`, `trusted-project`, `context>50`, `context>70`, `context>90`, `tokens>10k`. Example: `[{ "id": "cost", "when": "context>70" }, "branch"]`.
- Header: set `/header/enabled`, `/header/title`, and `/header/subtitle`.
- Widget: set `/widget/enabled`, `/widget/placement`, and `/widget/lines`.
- Welcome banner: set `/welcome/enabled` to false to suppress startup ASCII, or `/welcome/banner` to custom string lines.
- Tool display: set `/tools/expanded` and `/tools/renderStyle` (`pill`, `card`, `dense`, `minimal`). Render style affects `bash`, `edit`, `read`, and `grep`.
- Compatibility mode: set `/mode` to one of `full`, `theme-only`, `footer-only`, `widgets-only`, `status-only`.
- Persona swap: set `/persona` to one of `default`, `terse`, `arc`, `startrek`, `medieval`, `pirate`, `mlengineer`. Affects spinner frames and per-turn working-message rotation.
- One-shot launch preset: run `pi -e . --pie-preset <preset>` to apply a preset for that launch without writing `pie-ui.json`.
- Use `/pie gallery` to live-preview every preset without writing to config. j/k or h/l cycles, enter keeps current preview, q/esc restores previous config.
- Use `/pie diff <preset>` to preview what a clean preset apply would change before running `/pie preset <preset>`. Optional second arg `merge` previews merge-mode apply.
- `/pie history` shows the last 10 preset/import writes. `/pie undo` restores the most recent previous state and pops it from history. History lives at `~/.pi/agent/pie-history.json`, is capped at 50 entries, and is also appended as `pie:history`.
- `/pie import <path-or-url>` reads a local or remote `pie-ui.json`, validates it, asks for scope and confirms before writing. URL import uses `curl -fsSL` through `pi.exec`.
- `/pie capture` renders the active preset's tape via `vhs` to `assets/preview-<preset>.gif`. Requires `vhs`, `ttyd`, `ffmpeg` on PATH (install with `brew install vhs`). Regenerate tapes via `npm run assets:tapes` or render all via `npm run assets:capture`.
- `/pie share` writes `assets/share/<timestamp>/pie-ui.json`, `payload.json`, and a preview asset. Server upload is not implemented; use the printed `gh gist create ...` fallback.
- `npx fap capture-terminal --name <theme>` writes a Pi theme JSON from the current terminal ANSI palette.
- `/pie doctor` validates config, detects UI package conflicts, and reports missing `/pie capture` dependencies (`vhs`, `ttyd`, `ffmpeg`).
- Shortcut leader: `ctrl+alt+p`, then `p` preset picker, `g` gallery, `s` footer segments, `e` editor, `d` doctor, or `c` capture. `ctrl+p` is registered too, but Pi's default `app.model.cycleForward` reserves `ctrl+p`; rebind it in `~/.pi/agent/keybindings.json` and run `/reload` before using `ctrl+p` as the leader.
- Use `/pie edit` for guided changes, `/pie edit-json` for direct JSON edits with enum autocomplete, and `/pie export` to inspect final merged config.
- Prefer `pie_config` actions `set_preset`, `set_footer_segments`, `toggle_compact`, and `set_theme` over raw patching for common edits.

## Inter-extension Events

Fried Apple Pie emits the following events on `pi.events` (when present):

- `pie:preset-changed` — `{ from, to, scope, path, ts }`. Fires after `/pie preset` writes.
- `pie:mode-changed` — `{ from, to, scope, path, ts }`. Fires after `/pie mode` writes.
- `pie:persona-changed` — `{ from, to, scope, path, ts }`. Fires after `/pie persona` writes.

Other Pi extensions can subscribe to coordinate companion behavior (e.g. swap a footer renderer when preset changes).

## Validation
After every change, run `pie_config` action `validate` or use `/pie doctor`.
