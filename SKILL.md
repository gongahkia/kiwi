---
name: kumeyuri
description: Use kumeyuri to parse, lint, animate, render, export, play, embed, and serve Mermaid-compatible diagrams through its CLI, MCP server, Rust crates, WASM player, and docs/editor integrations.
---

# Kumeyuri

Use this skill when a task involves turning Mermaid source into deterministic kumeyuri output, checking Mermaid compatibility, wiring kumeyuri into an agent/editor/docs stack, or validating a kumeyuri release claim.

## Core model

- Treat kumeyuri as a Mermaid-to-frame-stream renderer, not a drop-in Mermaid.js replacement.
- Run `kumeyuri compat` or inspect `docs/compat.md`/`COVERAGE.md` before claiming diagram support.
- Animated roots and static-only roots are both useful output paths; static-only means the parser and renderer work but playback collapses to one frame.
- Mermaid init/frontmatter/config/theme/layout/click behavior is not the main compatibility surface unless `COVERAGE.md` says otherwise.

## CLI

- Render: `kumeyuri render diagram.mmd --format text|svg|gif|apng|webp|tui`.
- Play: `kumeyuri play diagram.mmd` or `kumeyuri play diagram.kumecast`.
- Export: `kumeyuri export diagram.mmd --format kumecast|kumecast-gz`.
- Convert: `kumeyuri convert diagram.kumecast --format svg|gif|text`.
- Lint: `kumeyuri lint diagram.mmd` or `kumeyuri lint --json diagram.mmd`.
- Watch: `kumeyuri watch diagram.mmd`.
- Themes: `kumeyuri theme list`, `kumeyuri theme show <name>`, `kumeyuri theme validate <file>`.
- Plugins: `kumeyuri plugin install|list|update|disable|remove`.

## MCP

Start stdio MCP:

```sh
kumeyuri mcp --transport stdio
```

Start HTTP+SSE MCP:

```sh
kumeyuri mcp --transport http-sse --bind 127.0.0.1:8000 --bearer-token "$KUMEYURI_MCP_BEARER_TOKEN"
```

MCP tools:

- `render_diagram`: render Mermaid source as text, SVG, GIF, APNG, WebP, or VTT.
- `play_diagram`: spawn local TUI playback for a file path.
- `lint_diagram`: return parser/layout diagnostics.
- `list_themes`: list bundled, project, and XDG themes.
- `list_diagram_types`: return roots, support level, and caveats.

Keep stdout clean for stdio MCP. Bind HTTP+SSE to loopback unless a real auth/TLS boundary exists.

## Embeds and integrations

- Rust crates: use `kumeyuri-core` for parse/layout/animation frames, renderer crates for SVG/raster/WASM surfaces.
- WASM/browser: use the `kumeyuri` package/web component for browser playback.
- Docs: use the mdBook preprocessor, Docusaurus/Astro/Quartz/rehype/remark packages where appropriate.
- Editors/actions: use the Neovim, VSCode, Obsidian, Logseq, and GitHub Action integrations from this repo when the target environment matches.
- Plugins: prefer the plugin ABI for optional renderers or diagram extensions instead of hard-coding external behavior into core.

## Verification

For local changes, prefer the smallest gate that covers the touched surface:

```sh
cargo fmt --all -- --check
cargo test --workspace
npm run test:compat
npm run test:mcp-server
npm run test:wasm-budget
```

For coverage claims:

```sh
npm run test:compat-versions
npm run test:coverage-gate
cargo test -p kumeyuri-cli --test cross_format_snapshots
cargo test -p kumeyuri-render-wasm all_supported_roots_have_wasm_output_hash_snapshots
```

For docs claims:

```sh
npm run docs:build
```

## Reporting

- Say "tracked roots" unless an external Mermaid docs/source check was performed.
- Label unverified Mermaid version claims as unverified.
- Distinguish "animated", "static-only", and "unsupported/no parser root".
- Mention exact output formats tested when reporting render parity.
