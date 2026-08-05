# ADR 0001: Storage

## Status

Accepted

## Context

wat needs public, team, and personal glossary layers with citations, audit history, search indexes, and self-host support. JSON-on-disk is simple for a seed corpus, but it becomes brittle once users can edit entries, review suggestions, and query across layers.

## Decision

Use Postgres as the day-one system of record.

## Rationale

- One datastore can serve CRUD, tenancy, audit logs, full-text search, trigram matching, and vector search.
- Migrations give explicit schema history for self-hosted installs.
- Transactions keep entry updates, source updates, and audit records consistent.
- Hosted and self-hosted deployments can use the same schema and query paths.
- JSON files remain useful as reviewed import deltas and seed fixtures, not as primary storage.

## Consequences

- Local development needs Docker or a reachable Postgres instance.
- The ingest pipeline must transform source data into migrations or seed scripts.
- Search quality depends on database extensions being present and tested.
