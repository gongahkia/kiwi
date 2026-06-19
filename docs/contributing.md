# Contributing

## Local Setup

Prereqs:

- Node.js with Corepack
- pnpm 10.33.0
- Docker, if working on Postgres-backed features

Install dependencies:

```sh
corepack enable
pnpm install
```

Common checks:

```sh
pnpm typecheck
pnpm lint
pnpm build
```

Run the web app:

```sh
pnpm dev
```

Run package tests:

```sh
pnpm --filter @wat/core test
pnpm --filter @wat/search test
pnpm --filter @wat/ingest test
```

Generate DB migrations after schema edits:

```sh
pnpm db:generate
```

## Pull Requests

Keep PRs scoped to one task or one tightly related task group. Include the user-visible behavior, verification commands, and any skipped checks.

Commit messages use conventional commits:

- `feat(scope): summary`
- `fix(scope): summary`
- `docs: summary`
- `test(scope): summary`
- `chore(scope): summary`

Do not mix generated build artifacts into source changes. If a task changes `TODO.md`, remove only the completed line whose done condition was verified.

## Scraper Authoring

Scrapers live under `packages/ingest/src/scrapers/`. A scraper should produce normalized entries and preserve provenance.

Each imported entry needs:

- stable `id`
- `term` and `term_normalized`
- one or more `expansions`
- `domains`
- short and long meaning text
- source URL, title, publisher, license, retrieved timestamp, snippet, and source quality
- confidence tier derived from source quality

Scrapers should not invent missing definitions. If a source does not support a claim, exclude the field or mark the entry for review.

Add or update tests in `packages/ingest/src/*test.ts` for parsing, license handling, deduplication, and confidence tier assignment. Prefer small fixtures that cover source edge cases without committing large raw downloads.

## Corpus Deltas

Importer output belongs in `data/deltas/<date>/`. Deltas should be reviewable JSON with added, changed, and removed entries separated where possible.

Before opening a corpus PR, run:

```sh
pnpm --filter @wat/ingest test
pnpm typecheck
```
