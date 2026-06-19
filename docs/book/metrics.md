# Metrics

![kumeyuri metrics](https://raw.githubusercontent.com/gongahkia/kumeyuri/main/metrics/dashboard.svg)

The dashboard is generated from committed repository-owned CSV snapshots:

| File | Purpose |
| --- | --- |
| `metrics/daily.csv` | Daily GitHub stars, GitHub forks, crates.io downloads, and npm downloads |
| `metrics/weekly.csv` | Monday-based weekly rollups and within-week deltas |
| `metrics/dashboard.svg` | SVG rendered by `kumeyuri-cli` from the weekly rollup |

Regenerate locally:

```sh
npm run metrics:weekly
npm run metrics:dashboard
```
