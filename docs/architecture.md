# Architecture

wat's target architecture is a Postgres-backed glossary with public, team, and personal layers exposed through web, browser extension, Slack, and MCP surfaces.

## System Diagram

```mermaid
flowchart LR
  subgraph Sources
    public_sources[Public docs and glossaries]
    team_sources[Team-authored entries]
    personal_sources[Personal entries]
  end

  subgraph Ingestion
    scrapers[Scrapers]
    deltas[JSON deltas]
    review_pr[Review PR]
    seed[Seed/import job]
  end

  subgraph Data
    postgres[(Postgres)]
    fts[tsvector index]
    trigram[pg_trgm index]
    vector[pgvector index]
    audit[audit_log]
  end

  subgraph API
    web_api[Next.js API]
    search_pkg[@wat/search]
    core_pkg[@wat/core]
  end

  subgraph Surfaces
    web[Web app]
    ext[Browser extension]
    slack[Slack app]
    mcp[MCP server]
  end

  public_sources --> scrapers --> deltas --> review_pr --> seed --> postgres
  team_sources --> web --> web_api --> postgres
  personal_sources --> web --> web_api --> postgres
  postgres --> fts
  postgres --> trigram
  postgres --> vector
  postgres --> audit
  web_api --> search_pkg
  search_pkg --> postgres
  web_api --> core_pkg
  web --> web_api
  ext --> web_api
  slack --> web_api
  mcp --> web_api
```

## Data Flow

Public corpus data starts in source-specific scrapers. Scrapers write reviewed JSON deltas, scheduled CI opens a PR, and accepted deltas are imported into Postgres with source URLs and license tags.

Team and personal entries are written through authenticated product surfaces. Entry changes write the target table and append audit records so reviews, imports, and admin edits have traceable before/after state.

Search reads the merged glossary layers in priority order: personal, team, public. Ranking combines lexical full-text, trigram fuzzy matching, vector similarity, domain tags, and context boosts through reciprocal rank fusion.

## Surface Flows

The web app owns interactive search, entry pages, contribution flows, team admin, install pages, and public corpus stats. It talks to the same API and packages used by other surfaces.

The browser extension sends selected text, hover tokens, or page context to lookup endpoints. Its target local behavior is recent-lookup caching and telemetry opt-in.

The Slack app handles slash commands, shortcuts, mentions, and admin definition commands. Slack workspace identity maps to a wat team after install.

The MCP server exposes read-oriented tools for agents and editors. It accepts a term plus optional context and returns ranked entries with citations.

## Storage Model

Postgres is the system of record. Public entries live in `entries`, team overlays in `team_entries`, personal overlays in `personal_entries`, and review state in `suggested_edits`.

Search indexes live beside the source rows: generated `tsvector` columns for lexical ranking, pg_trgm indexes for fuzzy matching, and pgvector indexes for semantic ranking.

## Trust Boundaries

Public data must carry provenance. Team and personal data require authenticated users. Admin-only workflows enforce role checks before mutating team entries, membership, domain tags, or settings.

External surfaces should not bypass authorization; browser, Slack, and MCP requests should resolve to the same team/user scope as web requests.
