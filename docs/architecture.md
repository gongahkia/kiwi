# Architecture

wat's target architecture is a Postgres-backed glossary with public, team, and personal layers exposed first through Slack, then Teams and other company workflow surfaces. The web app is API/admin infrastructure.

For contributor-facing DB layer flow and current implementation gaps, see [Developer Architecture Guide](developer-architecture.md).

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
    teams[Teams app]
    discord[Discord app]
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
  teams --> web_api
  discord --> web_api
  mcp --> web_api
```

## Data Flow

Public corpus data starts in source-specific scrapers. Scrapers write reviewed JSON deltas, scheduled CI opens a PR, and accepted deltas are imported into Postgres with source URLs and license tags.

Team and personal entries are written through authenticated product surfaces. Entry changes write the target table and append audit records so reviews, imports, and admin edits have traceable before/after state.

Search reads the merged glossary layers in priority order: personal, team, public. Ranking combines lexical full-text, trigram fuzzy matching, vector similarity, domain tags, and context boosts through reciprocal rank fusion.

## Surface Flows

The web app owns API routes, auth, entry pages, contribution review, team admin, install pages, and public corpus stats. It should not be the primary user workflow for company teams.

The browser extension sends selected text, hover tokens, or page context to lookup endpoints. Its target local behavior is recent-lookup caching and telemetry opt-in.

The Slack app is the first priority user surface. It handles slash commands, shortcuts, mentions, and admin definition commands. Slack workspace identity maps to a wat team after install.

Slack OAuth install uses signed state, exchanges the temporary code with Slack, encrypts returned bot/user tokens, and records the Slack workspace to wat team mapping. Runtime install storage supports local JSON or Postgres-backed `slack_installs`; uninstall and token-revocation events delete the workspace install. Slack suggestions write team-scoped review rows through `suggested_edits`.

The Teams app starts as an API-based message extension for search. It packages a Teams manifest, OpenAPI Description, and response rendering template that call `/api/v1/teams/search`, which returns a Teams-card-friendly wrapper around `/api/v1/search`. DB-backed `teams_installs` mappings are available for gateways or later SSO/bot flows; write flows and admin actions should wait for stronger user auth.

The Discord app uses signed HTTP interactions for slash and message commands. Guild identity maps to a wat team through `discord_installs` or `WAT_DISCORD_GUILD_MAP`; suggestions write `suggested_edits`, and admin-gated definitions write team entries through `/api/v1/custom-entries`.

The MCP server exposes read-oriented tools for agents and editors. It accepts a term plus optional context and returns ranked entries with citations.

## Storage Model

Postgres is the system of record. Public entries live in `entries`, team overlays in `team_entries`, personal overlays in `personal_entries`, and review state in `suggested_edits`.

Search indexes live beside the source rows: generated `tsvector` columns for lexical ranking, pg_trgm indexes for fuzzy matching, and pgvector indexes for semantic ranking.

## Trust Boundaries

Public data must carry provenance. Team and personal data require authenticated users. Admin-only workflows enforce role checks before mutating team entries, membership, domain tags, or settings.

External surfaces should not bypass authorization; browser, Slack, Discord, and MCP requests should resolve to the same team/user scope as web requests.
