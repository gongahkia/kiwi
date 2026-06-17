# Kumeyuri OpenCode Plugin

OpenCode integration for rendering Mermaid diagrams inline with kumeyuri.

It provides:

- `plugins/kumeyuri-render.ts`: an OpenCode plugin exposing the `kumeyuri_render` custom tool.
- `skills/kumeyuri-render/SKILL.md`: an OpenCode skill telling the agent when to call the tool.
- `scripts/render-mermaid-blocks.mjs`: a fallback Markdown transformer.

## Install In A Project

Copy the directories into your project config:

```sh
mkdir -p .opencode/plugins .opencode/skills .opencode/scripts
cp editors/opencode/kumeyuri-render/plugins/kumeyuri-render.ts .opencode/plugins/
cp -R editors/opencode/kumeyuri-render/skills/kumeyuri-render .opencode/skills/
cp editors/opencode/kumeyuri-render/scripts/render-mermaid-blocks.mjs .opencode/scripts/
```

Install the plugin helper dependency in `.opencode/package.json`:

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "^1.17.7"
  }
}
```

OpenCode runs `bun install` at startup for config dependencies.

## Development

```sh
bun install --cwd editors/opencode/kumeyuri-render
npm --prefix editors/opencode/kumeyuri-render test
```

Set `KUMEYURI_BIN=/path/to/kumeyuri` if `kumeyuri` is not on `PATH`.
