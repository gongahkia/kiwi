# Corpus Delta Rollback

Use this when a reviewed corpus refresh merged bad public entries, bad source metadata, or a bad removal.

## Inputs

- bad delta path: `data/deltas/<date>/<source>.json`
- known-good git ref: the commit, tag, or branch whose delta should be restored
- affected source name: the delta file basename without `.json`

## Restore

```sh
pnpm rollback:delta <known-good-ref> data/deltas/<date>/<source>.json
```

The helper reads the checked-in delta from `<known-good-ref>` with `git show`, validates that it is JSON, and replaces the working-tree delta file.

## Verify

```sh
pnpm --filter @wat/ingest summarize:delta data/deltas/<date>/<source>.json reports/corpus-refresh/<date>-<source>.md
pnpm --filter @wat/ingest lint:sources
pnpm --filter @wat/search bench
pnpm typecheck
```

If the bad delta was already imported into a running DB, rerun the public corpus import from the restored delta after these checks pass. If the import job is paused, keep it paused until the rollback PR is merged and deployed.

## Merge Path

1. Commit only the restored delta and regenerated report.
2. Link the bad refresh PR or deploy in the commit message.
3. Keep the failing scraper source disabled until a fixture reproduces the bad output and the scraper fix passes review.
4. After merge, verify `/readyz` and `GET /api/v1/search?q=API` on the affected environment.
