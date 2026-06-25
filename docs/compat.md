# Mermaid compatibility

Last checked: 2026-06-25.

Upstream reference: Mermaid docs `11.15.0`.

Detailed coverage lives in [`../COVERAGE.md`](../COVERAGE.md). This file is the
release-facing compatibility tracker.

## Current parser roots

| Status | Mermaid roots/families |
| --- | --- |
| Animated partial support | `graph`, `flowchart`, `sequenceDiagram`, `stateDiagram`, `stateDiagram-v2`, `classDiagram`, `erDiagram`, `gantt`, `pie`, `mindmap`, `journey`, `gitGraph`, `timeline` |
| Static-only partial support | `quadrantChart`, `zenuml`, `sankey`, `sankey-beta`, `xychart`, `xychart-beta`, `block`, `packet`, `packet-beta`, `kanban`, `architecture-beta`, `radar-beta`, `eventmodeling`, `treemap-beta`, `venn-beta`, `ishikawa-beta`, `wardley-beta`, `treeView-beta`, `requirementDiagram`, `C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, `C4Deployment`, `cynefin-beta`, `railroad-diagram`, `swimlane` |
| No parser root | None tracked |

## Compatibility policy

- kumeyuri consumes Mermaid source; it does not embed Mermaid's JavaScript parser.
- Supported roots are partial unless `COVERAGE.md` says otherwise.
- Unsupported roots fail at parser-header detection instead of rendering partial output.
- Mermaid config/frontmatter/init/theme/layout/click behavior is not compatibility
  surface today, except `%%{ animate: ... }%%` for kumeyuri animation.
- `site/parity.json` is the release-facing fixture delta report. Current local
  evidence: kumeyuri renders 31/31 fixtures; Mermaid CLI renders 28/31. The
  Mermaid CLI deltas are `cynefin-beta`, `railroad-diagram`, and `swimlane`.
- `site/motion.json` is the animation quality report. Current local evidence:
  11 animated partial families, 20 static-only partial families, 0 gate failures.

## Release checklist

Run this before any release that claims Mermaid compatibility:

1. Check the Mermaid docs sidebar version and diagram-type list.
2. Diff the list against `COVERAGE.md` and this file.
3. If Mermaid added a root, add it as `No parser root` unless parser/render support
   lands in the same release.
4. If parser/render support changed, update the status row and snapshot count in
   `COVERAGE.md`.
5. Run parser, renderer, WASM, docs, and sanitizer gates listed in `TODO.md`.

## Evidence commands

```bash
rg -n "pub enum DiagramKind|parse_.*_header|C4Context|C4Container|C4Component|C4Dynamic|C4Deployment" crates/kumeyuri-core/src
find tests/snapshots -path '*/input/*.mmd' -print | sed 's#tests/snapshots/##; s#/input/.*##' | sort | uniq -c
npm run test:compat
npm run test:compat-versions
npm run test:mermaid-parity
npm run test:animation-quality
npm run test:coverage-gate
kumeyuri compat --json
kumeyuri audit-mermaid ./docs --json
npm run docs:build
```
