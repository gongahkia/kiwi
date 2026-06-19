# Metrics

This directory stores project-owned growth and release-health metrics without
requiring an external analytics service.

Planned generated files:

* `daily.csv` - raw daily snapshots from GitHub, crates.io, and npm.
* `weekly.csv` - weekly rollups derived from `daily.csv`.
* `dashboard.svg` - rendered weekly summary for README/docs embedding.

Until the scheduled polling workflow is added, keep committed files limited to
schema documentation and small hand-maintained examples.
