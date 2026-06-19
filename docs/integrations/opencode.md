# opencode

`editors/opencode/kumeyuri-render` provides an opencode plugin, skill, and
Markdown transformer.

Copy the integration into a project:

```sh
mkdir -p .opencode/plugins .opencode/skills .opencode/scripts
cp editors/opencode/kumeyuri-render/plugins/kumeyuri-render.ts .opencode/plugins/
cp -R editors/opencode/kumeyuri-render/skills/kumeyuri-render .opencode/skills/
cp editors/opencode/kumeyuri-render/scripts/render-mermaid-blocks.mjs .opencode/scripts/
```

Install `@opencode-ai/plugin` in `.opencode/package.json`. Set `KUMEYURI_BIN`
if the `kumeyuri` binary is not on `PATH`.
