# DB Schema

Source of truth: `packages/db/src/schema.ts` and Drizzle migrations in `packages/db/drizzle/`.

```mermaid
erDiagram
  teams {
    text id PK
    text name
    text email_domain UK
    timestamptz created_at
    jsonb settings_jsonb
  }

  users {
    text id PK
    text email UK
    text team_id FK
    user_role role
    timestamptz created_at
  }

  entries {
    text id PK
    text term
    text term_normalized
    text_array expansions
    text_array domains
    text meaning_short
    text meaning_long
    text coiner
    integer year_coined
    text confidence_tier
    text license
    text layer
    text team_id
    timestamptz created_at
    timestamptz updated_at
    boolean deprecated
    text deprecated_reason
    text_array aliases
    text_array related_terms
    tsvector tsvector
    vector_384 embedding
  }

  sources {
    text id PK
    text entry_id FK
    integer position
    text url
    text title
    text publisher
    text license
    timestamptz retrieved_at
    text snippet
    text source_quality
  }

  examples {
    text id PK
    text entry_id FK
    integer position
    text body
  }

  team_entries {
    text id PK
    text term
    text term_normalized
    text_array expansions
    text_array domains
    text meaning_short
    text meaning_long
    text coiner
    integer year_coined
    text confidence_tier
    text license
    text layer
    text team_id FK
    timestamptz created_at
    timestamptz updated_at
    boolean deprecated
    text deprecated_reason
    text_array aliases
    text_array related_terms
    tsvector tsvector
    vector_384 embedding
  }

  personal_entries {
    text id PK
    text term
    text term_normalized
    text_array expansions
    text_array domains
    text meaning_short
    text meaning_long
    text coiner
    integer year_coined
    text confidence_tier
    text license
    text layer
    text user_id FK
    timestamptz created_at
    timestamptz updated_at
    boolean deprecated
    text deprecated_reason
    text_array aliases
    text_array related_terms
    tsvector tsvector
    vector_384 embedding
  }

  audit_log {
    text id PK
    text actor_id FK
    text action
    text target_type
    text target_id
    jsonb before_jsonb
    jsonb after_jsonb
    timestamptz at
  }

  suggested_edits {
    text id PK
    text actor_id FK
    text target_type
    text target_id
    suggested_edit_status status
    jsonb before_jsonb
    jsonb after_jsonb
    timestamptz created_at
    text reviewed_by FK
    timestamptz reviewed_at
  }

  teams ||--o{ users : owns
  teams ||--o{ team_entries : scopes
  users ||--o{ personal_entries : owns
  users ||--o{ audit_log : acts
  users ||--o{ suggested_edits : submits
  users ||--o{ suggested_edits : reviews
  entries ||--o{ sources : cites
  entries ||--o{ examples : demonstrates
```

## Enums

- `user_role`: `admin`, `member`
- `suggested_edit_status`: `pending`, `approved`, `rejected`

## Generated columns

- `entries.tsvector`, `team_entries.tsvector`, and `personal_entries.tsvector` are generated from term, expansions, meanings, aliases, and related terms.
- `entries.embedding`, `team_entries.embedding`, and `personal_entries.embedding` are `vector(384)` columns for semantic search.
- `sources.entry_id` cascades on entry delete.
- `examples.entry_id` cascades on entry delete.

## Constraints

- `teams.email_domain` is unique.
- `users.email` is unique.
- `team_entries.team_id` cascades on team delete.
- `personal_entries.user_id` cascades on user delete.
- Entry confidence tiers are constrained to `T1`, `T2`, `T3`, `T4`.
- Source quality is constrained to `canonical`, `secondary`, `community`.
- Overlay layers are constrained to `team` and `personal` for their respective tables.
