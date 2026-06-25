# Migration Audit

Use `audit-mermaid` before replacing Mermaid.js on an existing site.

```bash
kumeyuri audit-mermaid ./docs
kumeyuri audit-mermaid ./docs ./site/content --json > kumeyuri-audit.json
```

The command scans:

- `.mmd` and `.mermaid` files;
- Markdown and MDX Mermaid fences;
- nested directories, excluding `.git`, `node_modules`, `target`, and `.playwright-cli`.

Each finding reports:

- file path and source line;
- detected root;
- `animated-partial`, `static-only-partial`, or `unsupported`;
- parse status, render status, and frame count;
- warnings for Mermaid frontmatter/init/config/theme/layout/click behavior;
- parse/render error and migration suggestion when available.

Use the JSON output in CI to block site migrations that introduce unsupported
roots or Mermaid config that kumeyuri does not interpret.
