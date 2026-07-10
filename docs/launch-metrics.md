# Launch Metrics

Track these values daily for 14 consecutive UTC dates after launch:

- `github_stars`
- `hosted_searches`
- `extension_installs`
- `slack_installs`
- `mcp_installs`
- `docs_visits`

CSV format:

```csv
date,github_stars,hosted_searches,extension_installs,slack_installs,mcp_installs,docs_visits
2026-07-10,0,0,0,0,0,0
```

Validate the completed file before marking launch metrics done:

```sh
pnpm launch:metrics:check -- reports/launch/launch-metrics.csv
```

Use UTC dates, one row per day, non-negative integer counts only. Keep source links or dashboard screenshots with the launch issue; the CSV is the normalized acceptance record.
