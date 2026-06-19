# ADR 0002: Search

## Status

Accepted

## Context

wat must search short acronyms, expanded terms, typo-heavy queries, and context-rich phrases. It also needs self-host installs to work without a managed search service.

## Decision

Use Postgres-only hybrid search:

- BM25-style lexical ranking through `tsvector` and `ts_rank_cd`.
- Vector similarity through `pgvector` with 384-dimensional embeddings.
- Fuzzy typo fallback through `pg_trgm`.
- Reciprocal Rank Fusion in application code to combine ranked result sets.

## Rationale

- Postgres keeps indexing, filtering, tenancy, and citations in one transactional system.
- `pg_trgm` handles short-token typos better than full-text search alone.
- Vector search handles semantic context for overloaded acronyms.
- Reciprocal Rank Fusion lets each signal contribute without forcing incomparable raw scores onto one scale.
- A single database reduces self-host operational burden.

## Consequences

- Postgres 16 plus `vector` and `pg_trgm` extensions are required.
- Search migrations must create and verify all required indexes.
- Benchmarking must track each signal separately and the fused score.
- If scale outgrows one Postgres instance, the first mitigation is read replicas and index tuning, not a separate search engine.
