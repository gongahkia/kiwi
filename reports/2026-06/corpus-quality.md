# Corpus Quality KPI: 2026-06

Date: 2026-06-19

Scope: `packages/ingest/seeds/manual.json`

## Summary

| Metric                             | Value |
| ---------------------------------- | ----: |
| Public entries                     |    52 |
| Exact-term top-1 hit-rate          |   77% |
| Exact-term top-5 hit-rate          |  100% |
| Source coverage                    |  100% |
| Entries missing source URL/license |     0 |

## Hit-Rate

Measured against all 52 committed manual seed entries by querying `GET /api/v1/search?q=<term>&limit=5` on a production Next server.

Result:

- top-1: 40 / 52
- top-5: 52 / 52
- top-5 misses: 0

## Drift

This is the first committed monthly corpus-quality report, so it establishes the baseline.

Baseline drift for this report:

| Change type | Count |
| ----------- | ----: |
| Added       |     0 |
| Changed     |     0 |
| Removed     |     0 |

Future reports should compare `packages/ingest/seeds/manual.json` against the prior monthly report baseline.

## Source Coverage

Verification command:

```sh
pnpm --filter @wat/ingest lint:sources
```

Result:

```text
source coverage ok: 52 entries checked
```
