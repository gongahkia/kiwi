# Metrics

This directory stores project-owned growth and release-health metrics without
requiring an external analytics service.

Planned generated files:

* `daily.csv` - raw daily snapshots from GitHub, crates.io, and npm.
* `weekly.csv` - weekly rollups derived from `daily.csv`.
* `dashboard.svg` - rendered weekly summary for README/docs embedding.
* `archive/YYYY/dashboard.svg` - annual dashboard snapshot for historical
  comparison.

CSV schema:

* `daily.csv`: `date,github_stars,github_forks,crates_downloads,npm_downloads`
* `weekly.csv`: Monday-based `week_start`, observed `week_end`, final weekly
  values, and deltas from first to last observed row in the week.

Regenerate weekly rollups with:

```sh
node scripts/aggregate-weekly-metrics.mjs
```

Append or update today's row with:

```sh
METRICS_GITHUB_REPO=kumeyuri/kumeyuri node scripts/poll-daily-metrics.mjs
```

Regenerate the dogfooded dashboard SVG with:

```sh
node scripts/generate-metrics-dashboard.mjs
```

Archive the current dashboard for the current year with:

```sh
node scripts/archive-metrics-dashboard.mjs
```
