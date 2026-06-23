# Fried Apple Pie

Agent-editable Pi UI presets, themes, and config.

<div align="center">
  <img width=85% alt="Fried Apple Pie preset gallery" src="./assets/fried-apple-pie-gallery.png" />
</div>

## Install

```sh
pi install ./fried-apple-pie
```

For one run:

```sh
pi -e ./fried-apple-pie
```

## Presets

- `minimal`
- `claude-inspired`
- `opencode-inspired`
- `codex-inspired`
- `gemini-inspired`

These are inspired presets, not exact clones.

## Commands

```txt
/pie
/pie preset minimal
/pie edit
/pie welcome
/pie export
/pie preset claude-inspired
/pie show
/pie doctor
/pie reset
```

## Agent Tool

The package registers `pie_config` so Pi can read, validate, patch, and apply UI config without guessing file format. It supports a JSON Patch subset: `add`, `replace`, `remove`.

Config paths:

```txt
~/.pi/agent/pie-ui.json
.pi/pie-ui.json
```

Project config overrides global config only when the project is trusted.

Schema:

```txt
schema/pie-ui.schema.json
```

## Config

```json
{
  "preset": "codex-inspired",
  "theme": "fried-apple-pie-codex",
  "footer": {
    "enabled": true,
    "segments": ["model", "thinking", "cwd", "branch", "status", "context"]
  },
  "header": {
    "enabled": true,
    "title": "Codex-inspired",
    "subtitle": "dense agent workspace"
  },
  "tools": {
    "expanded": false
  }
}
```

Footer segments: `model`, `thinking`, `cwd`, `branch`, `status`, `context`, `tokens`, `cost`, `preset`.

## Compatibility

Fried Apple Pie owns the header/footer/widget surfaces while enabled. If another package also controls those surfaces, use `/pie doctor` to spot likely conflicts and disable one side.

## Verify

```sh
npm install
npm run verify
```
