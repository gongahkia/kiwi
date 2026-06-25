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
    text_array contemporaries
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

  entry_embedding_jobs {
    text entry_id PK
    text reason
    text status
    timestamptz requested_at
    timestamptz updated_at
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
    text_array contemporaries
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
    text_array contemporaries
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
    text team_id FK
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

  slack_installs {
    text id PK
    text slack_team_id UK
    text slack_team_name
    text enterprise_id
    text enterprise_name
    text team_id FK
    text app_id
    text bot_user_id
    text installer_slack_user_id
    jsonb bot_token_encrypted
    jsonb user_token_encrypted
    text_array bot_scopes
    text_array user_scopes
    timestamptz installed_at
    timestamptz updated_at
  }

  teams_installs {
    text id PK
    text microsoft_tenant_id UK
    text tenant_name
    text team_id FK
    text app_id
    text auth_type
    text api_secret_registration_id
    text service_url
    text installed_by
    timestamptz installed_at
    timestamptz updated_at
  }

  discord_installs {
    text id PK
    text discord_guild_id UK
    text guild_name
    text team_id FK
    text application_id
    text bot_user_id
    text installer_discord_user_id
    text_array admin_role_ids
    timestamptz installed_at
    timestamptz updated_at
  }

  teams ||--o{ users : owns
  teams ||--o{ team_entries : scopes
  teams ||--o{ slack_installs : connects
  teams ||--o{ teams_installs : connects
  teams ||--o{ discord_installs : connects
  teams ||--o{ suggested_edits : reviews
  users ||--o{ personal_entries : owns
  users ||--o{ audit_log : acts
  users ||--o{ suggested_edits : submits
  users ||--o{ suggested_edits : reviews
  entries ||--o{ sources : cites
  entries ||--o{ examples : demonstrates
  entries ||--o| entry_embedding_jobs : queues
```

## Enums

- `user_role`: `admin`, `member`
- `suggested_edit_status`: `pending`, `approved`, `rejected`

## Generated columns

- `entries.tsvector`, `team_entries.tsvector`, and `personal_entries.tsvector` are generated from term, expansions, meanings, aliases, related terms, and contemporaries.
- `entries.embedding`, `team_entries.embedding`, and `personal_entries.embedding` are `vector(384)` columns for semantic search.
- `sources.entry_id` cascades on entry delete.
- `examples.entry_id` cascades on entry delete.
- `entry_embedding_jobs.entry_id` cascades on entry delete and is maintained by `entries_embedding_enqueue_trigger`.

## Indexes

- `entries_tsvector_gin_idx`: GIN index on `entries.tsvector`.
- `entries_embedding_hnsw_idx`: HNSW index on `entries.embedding` with `vector_cosine_ops`.
- `entries_term_normalized_trgm_idx`: GIN trigram index on `entries.term_normalized`.
- `entries_term_layer_team_unique_idx`: unique partial index on active `(term_normalized, layer, team_id)` rows, with `NULLS NOT DISTINCT`.
- `slack_installs_slack_team_id_unique_idx`: unique index mapping one Slack workspace install to one wat team.
- `slack_installs_team_id_idx`: lookup index for installs by wat team.
- `teams_installs_microsoft_tenant_id_unique_idx`: unique index mapping one Microsoft tenant install to one wat team.
- `teams_installs_team_id_idx`: lookup index for Teams installs by wat team.
- `discord_installs_discord_guild_id_unique_idx`: unique index mapping one Discord guild install to one wat team.
- `discord_installs_team_id_idx`: lookup index for Discord installs by wat team.
- `suggested_edits_team_id_status_idx`: lookup index for team-scoped review queues by status.

## Constraints

- `teams.email_domain` is unique.
- `users.email` is unique.
- `team_entries.team_id` cascades on team delete.
- `slack_installs.team_id` cascades on team delete.
- `teams_installs.team_id` cascades on team delete.
- `discord_installs.team_id` cascades on team delete.
- `suggested_edits.team_id` cascades on team delete.
- `personal_entries.user_id` cascades on user delete.
- Entry confidence tiers are constrained to `T1`, `T2`, `T3`, `T4`.
- Source quality is constrained to `canonical`, `secondary`, `community`.
- Embedding job reason is constrained to `insert`, `update`; status is constrained to `pending`, `processing`, `done`, `failed`.
- Overlay layers are constrained to `team` and `personal` for their respective tables.
