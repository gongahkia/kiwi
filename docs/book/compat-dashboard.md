# Compatibility Dashboard

The public site publishes three machine-readable files:

| File | Purpose |
| --- | --- |
| `site/compat.json` | Declared kumeyuri support matrix from `kumeyuri compat --json`. |
| `site/parity.json` | Fixture-by-fixture comparison between Mermaid CLI and kumeyuri. |
| `site/motion.json` | Animation quality gate output for frame counts, durations, SVG motion mode, and reduced-motion CSS. |

Current checked-in evidence for Mermaid `11.15.0`:

| Metric | Value |
| --- | ---: |
| Tracked families | 31 |
| kumeyuri parsed/rendered fixtures | 31 / 31 |
| Mermaid CLI rendered fixtures | 28 / 31 |
| Animated partial families | 11 |
| Static-only partial families | 20 |
| Unsupported tracked roots | 0 |

The three Mermaid CLI deltas are `cynefin-beta`, `railroad-diagram`, and
`swimlane`, which return `UnknownDiagramError` in the local Mermaid CLI parity
harness. kumeyuri renders them as static-only partial schematics.

Run the checks:

```bash
npm run test:compat
npm run test:compat-versions
npm run test:mermaid-parity
npm run test:animation-quality
```

When local Chromium sandboxing prevents Mermaid CLI from starting, regenerate
only kumeyuri-side evidence explicitly:

```bash
node scripts/check-mermaid-parity.mjs --write --skip-mermaid
```

Do not use skip mode for release claims that compare against Mermaid CLI output.
