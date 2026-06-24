# wat

![TypeScript](https://img.shields.io/badge/TypeScript-6.x-3178c6) ![Next.js](https://img.shields.io/badge/Next.js-15-black) ![pnpm](https://img.shields.io/badge/pnpm-10-f69220) ![License](https://img.shields.io/badge/license-MIT-green)

Layered glossary lookup for tech acronyms and team jargon. wat combines public sourced entries with team and personal overlays across web, browser extension, Slack, MCP, and editor surfaces.

![wat search UI](docs/assets/web-search.png)

## Maturity

| Path | Status | Use now |
| --- | --- | --- |
| Local demo | Works | Run the web app against checked-in seed data. |
| Self-host | Experimental | Compose/Postgres docs and scripts exist; some product state is still in-memory. |
| Hosted beta | Not live | Hosted auth, DB-backed overlays, monitoring, and per-team keys are still TODO. |
| Browser extension | Developer build | Build locally or deploy by enterprise policy; login/pairing and store releases are TODO. |
| Slack | Scaffolded | Bolt handlers, tests, auth headers, and rate limits exist; OAuth install and deployed runtime wiring are TODO. |
| MCP | Local stdio server | Works from a clone after build; npm package, hosted/API backing, and catalog listings are TODO. |

See [Limitations](docs/limitations.md) for the current unsupported areas.

## Local Demo

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

## Install Paths

Self-host:

```sh
docker compose up --build
```

Then follow [Self-Host](docs/self-host.md) and [Migration Runbook](docs/migration-runbook.md) for migrations, backups, restore, and rollback.

Browser extension:

```sh
pnpm --filter @wat/ext dev
pnpm --filter @wat/ext build
pnpm --filter @wat/ext zip
```

Slack:

```sh
pnpm --filter @wat/slack build
pnpm --filter @wat/slack test
```

MCP:

```sh
pnpm --filter @wat/mcp build
node apps/mcp/dist/index.js
```

## Workspace

- `apps/web`: Next.js App Router web app and REST API routes
- `apps/slack`: Slack app scaffold
- `apps/mcp`: MCP server scaffold
- `apps/lsp`: LSP hover server for editor integrations
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
- [Developer architecture](docs/developer-architecture.md)
- [Limitations](docs/limitations.md)
- [Migration runbook](docs/migration-runbook.md)
- [Security](docs/security.md)
- [Security model](docs/security-model.md)
- [Troubleshooting](docs/troubleshooting.md)
