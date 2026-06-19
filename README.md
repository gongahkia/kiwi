# wat

![TypeScript](https://img.shields.io/badge/TypeScript-6.x-3178c6) ![Next.js](https://img.shields.io/badge/Next.js-15-black) ![pnpm](https://img.shields.io/badge/pnpm-10-f69220) ![License](https://img.shields.io/badge/license-MIT-green)

Layered glossary lookup for tech acronyms and team jargon. Public corpus, team overlay, personal overlay, citations, and multi-surface delivery.

![wat search UI](docs/assets/web-search.png)

## Install

```sh
corepack enable
pnpm install
pnpm typecheck
pnpm --filter @wat/web build
```

Run the web app:

```sh
pnpm dev
```

Open `http://localhost:3000`.

## Workspace

- `apps/web`: Next.js App Router web app and REST API routes
- `apps/slack`: Slack app scaffold
- `apps/mcp`: MCP server scaffold
- `extensions/browser`: browser extension scaffold
- `packages/core`: shared schema, normalization, validation, merge logic
- `packages/db`: Drizzle schema and migrations
- `packages/search`: ranking and search primitives
- `packages/ingest`: corpus ingestion helpers and scraper utilities

## Current Features

- public seed corpus with cited entries
- instant web search backed by local seed data
- disambiguated result cards with source counts and confidence chips
- domain filtering and keyboard navigation
- Markdown citation copy buttons
- entry permalinks, share links, and generated Open Graph images
- corpus stats at `/stats`

## Checks

```sh
pnpm lint
pnpm typecheck
pnpm build
pnpm --filter @wat/core test
pnpm --filter @wat/search test
pnpm --filter @wat/ingest test
```

## Docs

- [Architecture](docs/architecture.md)
- [API](docs/api.md)
- [Contributing](docs/contributing.md)
- [Security](docs/security.md)
