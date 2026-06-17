# Kumeyuri Claude Code Plugin

Claude Code plugin that adds `/kumeyuri-render`.

The skill renders Mermaid fenced code blocks inline with `kumeyuri render`, appending text or SVG output directly below each source fence.

## Development

Run from the repository root:

```sh
claude --plugin-dir ./editors/claude-code/kumeyuri-render
```

Validate the plugin:

```sh
claude plugin validate editors/claude-code/kumeyuri-render
```

Run script tests:

```sh
npm --prefix editors/claude-code/kumeyuri-render test
```

If the `kumeyuri` binary is not on `PATH`, set `KUMEYURI_BIN` or pass `--kumeyuri` to the script.
