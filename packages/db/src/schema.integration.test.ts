import { execFileSync } from "node:child_process";

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Client } from "pg";
import { GenericContainer, type StartedTestContainer, Wait } from "testcontainers";

import { applyMigrations } from "./migrate.js";
import { seedPublicCorpus } from "./seed-public.js";

let client: Client;
let container: StartedTestContainer;

const shouldRunContainerTests = process.env.CI === "true" || hasDockerRuntime();

describe.skipIf(!shouldRunContainerTests)("db schema integration", () => {
  beforeAll(async () => {
    container = await new GenericContainer("pgvector/pgvector:pg16")
      .withEnvironment({
        POSTGRES_DB: "wat",
        POSTGRES_PASSWORD: "wat",
        POSTGRES_USER: "wat"
      })
      .withExposedPorts(5432)
      .withWaitStrategy(Wait.forListeningPorts())
      .start();

    client = await connectWithRetry(
      `postgres://wat:wat@${container.getHost()}:${container.getMappedPort(5432)}/wat`
    );
    await applyMigrations(client);
  }, 120_000);

  afterAll(async () => {
    await client?.end();
    await container?.stop();
  }, 30_000);

  it("applies required extensions", async () => {
    const { rows } = await client.query<{ extname: string }>(
      "select extname from pg_extension where extname in ('vector', 'pg_trgm') order by extname"
    );

    expect(rows.map((row) => row.extname)).toEqual(["pg_trgm", "vector"]);
  });

  it("skips already applied migrations", async () => {
    const before = await migrationCount();

    await applyMigrations(client);

    expect(await migrationCount()).toBe(before);
  });

  it("seeds public corpus idempotently without deleting scoped overlays", async () => {
    await insertTeam("team_public_seed", "public-seed.example");
    await insertUser("user_public_seed", "team_public_seed");
    await insertTeamEntry("team_entry_public_seed", "team_public_seed", ["Kafka"]);
    await insertPersonalEntry("personal_entry_public_seed", "user_public_seed", ["OIDC"]);

    try {
      expect(await seedPublicCorpus(client, { limit: 3 })).toEqual({ count: 3 });
      expect(await seedPublicCorpus(client, { limit: 3 })).toEqual({ count: 3 });

      expect(await rowCount("entries", "id like 'seed-%'")).toBe(3);
      expect(await rowCount("sources", "entry_id like 'seed-%'")).toBe(3);
      expect(await rowCount("examples", "entry_id like 'seed-%'")).toBe(3);
      expect(await rowCount("team_entries", "id = 'team_entry_public_seed'")).toBe(1);
      expect(await rowCount("personal_entries", "id = 'personal_entry_public_seed'")).toBe(1);
    } finally {
      await client.query("delete from entries where id like 'seed-%'");
    }
  });

  it("creates entry rows", async () => {
    await insertEntry("entry_crud", "API", "api", ["Application Programming Interface"]);

    const { rows } = await client.query<{ term: string }>(
      "select term from entries where id = 'entry_crud'"
    );
    expect(rows[0]?.term).toBe("API");
  });

  it("updates entry rows", async () => {
    await insertEntry("entry_update", "DOM", "dom", ["Document Object Model"]);
    await client.query("update entries set meaning_short = 'updated' where id = 'entry_update'");

    const { rows } = await client.query<{ meaning_short: string }>(
      "select meaning_short from entries where id = 'entry_update'"
    );
    expect(rows[0]?.meaning_short).toBe("updated");
  });

  it("deletes entry rows", async () => {
    await insertEntry("entry_delete", "CSS", "css", ["Cascading Style Sheets"]);
    await client.query("delete from entries where id = 'entry_delete'");

    const { rows } = await client.query<{ count: number }>(
      "select count(*)::int as count from entries where id = 'entry_delete'"
    );
    expect(rows[0]?.count).toBe(0);
  });

  it("generates tsvector from term", async () => {
    await insertEntry("entry_tsv_term", "GraphQL", "graphql", ["Graph Query Language"]);

    const { rows } = await client.query<{ matches: boolean }>(
      "select tsvector @@ plainto_tsquery('english', 'graphql') as matches from entries where id = 'entry_tsv_term'"
    );
    expect(rows[0]?.matches).toBe(true);
  });

  it("generates tsvector from expansions", async () => {
    await insertEntry("entry_tsv_expansion", "JWT", "jwt", ["JSON Web Token"]);

    const { rows } = await client.query<{ matches: boolean }>(
      "select tsvector @@ plainto_tsquery('english', 'token') as matches from entries where id = 'entry_tsv_expansion'"
    );
    expect(rows[0]?.matches).toBe(true);
  });

  it("round-trips contemporaries and includes them in public entry tsvectors", async () => {
    await insertEntry(
      "entry_contemporary_public",
      "Event Stream",
      "event stream",
      ["Event Stream"],
      false,
      ["Kafka"]
    );

    const { rows } = await client.query<{ contemporaries: string[]; matches: boolean }>(
      "select contemporaries, tsvector @@ plainto_tsquery('english', 'kafka') as matches from entries where id = 'entry_contemporary_public'"
    );
    expect(rows[0]).toEqual({ contemporaries: ["Kafka"], matches: true });
  });

  it("round-trips contemporaries and includes them in team entry tsvectors", async () => {
    await insertTeam("team_contemporary", "contemporary.example");
    await insertTeamEntry("team_entry_contemporary", "team_contemporary", ["Kafka"]);

    const { rows } = await client.query<{ contemporaries: string[]; matches: boolean }>(
      "select contemporaries, tsvector @@ plainto_tsquery('english', 'kafka') as matches from team_entries where id = 'team_entry_contemporary'"
    );
    expect(rows[0]).toEqual({ contemporaries: ["Kafka"], matches: true });
  });

  it("round-trips contemporaries and includes them in personal entry tsvectors", async () => {
    await insertTeam("team_personal_contemporary", "personal-contemporary.example");
    await insertUser("user_contemporary", "team_personal_contemporary");
    await insertPersonalEntry("personal_entry_contemporary", "user_contemporary", ["Kafka"]);

    const { rows } = await client.query<{ contemporaries: string[]; matches: boolean }>(
      "select contemporaries, tsvector @@ plainto_tsquery('english', 'kafka') as matches from personal_entries where id = 'personal_entry_contemporary'"
    );
    expect(rows[0]).toEqual({ contemporaries: ["Kafka"], matches: true });
  });

  it("regenerates tsvector on update", async () => {
    await insertEntry("entry_tsv_update", "URI", "uri", ["Uniform Resource Identifier"]);
    await client.query(
      "update entries set meaning_long = 'websocket transport update' where id = $1",
      ["entry_tsv_update"]
    );

    const { rows } = await client.query<{ matches: boolean }>(
      "select tsvector @@ plainto_tsquery('english', 'websocket') as matches from entries where id = 'entry_tsv_update'"
    );
    expect(rows[0]?.matches).toBe(true);
  });

  it("rejects sources without an entry", async () => {
    await expect(
      client.query(
        "insert into sources (id, entry_id, position, url, title, publisher, license, retrieved_at, snippet, source_quality) values ('source_bad', 'missing', 0, 'https://example.com', 'title', 'publisher', 'MIT', now(), 'snippet', 'canonical')"
      )
    ).rejects.toMatchObject({ code: "23503" });
  });

  it("cascades sources when entries are deleted", async () => {
    await insertEntry("entry_source_cascade", "CORS", "cors", ["Cross-Origin Resource Sharing"]);
    await client.query(
      "insert into sources (id, entry_id, position, url, title, publisher, license, retrieved_at, snippet, source_quality) values ('source_cascade', 'entry_source_cascade', 0, 'https://example.com/cors', 'CORS', 'Example', 'MIT', now(), 'snippet', 'canonical')"
    );
    await client.query("delete from entries where id = 'entry_source_cascade'");

    const { rows } = await client.query<{ count: number }>(
      "select count(*)::int as count from sources where id = 'source_cascade'"
    );
    expect(rows[0]?.count).toBe(0);
  });

  it("rejects examples without an entry", async () => {
    await expect(
      client.query(
        "insert into examples (id, entry_id, position, body) values ('example_bad', 'missing', 0, 'body')"
      )
    ).rejects.toMatchObject({ code: "23503" });
  });

  it("rejects duplicate active terms in the same layer", async () => {
    await insertEntry("entry_unique_a", "SSO", "sso", ["Single Sign-On"]);

    await expect(
      insertEntry("entry_unique_b", "SSO", "sso", ["Single Sign-On"])
    ).rejects.toMatchObject({
      code: "23505"
    });
  });

  it("allows duplicate deprecated terms in the same layer", async () => {
    await insertEntry("entry_deprecated_a", "PWA", "pwa", ["Progressive Web Application"], true);
    await insertEntry("entry_deprecated_b", "PWA", "pwa", ["Progressive Web Application"], true);

    const { rows } = await client.query<{ count: number }>(
      "select count(*)::int as count from entries where term_normalized = 'pwa'"
    );
    expect(rows[0]?.count).toBe(2);
  });

  it("enqueues embedding jobs on entry insert", async () => {
    await insertEntry("entry_embedding_insert", "SCIM", "scim", [
      "System for Cross-domain Identity Management"
    ]);

    const { rows } = await client.query<{ reason: string; status: string }>(
      "select reason, status from entry_embedding_jobs where entry_id = 'entry_embedding_insert'"
    );
    expect(rows[0]).toEqual({ reason: "insert", status: "pending" });
  });

  it("requeues embedding jobs on searchable entry update", async () => {
    await insertEntry("entry_embedding_update", "OIDC", "oidc", ["OpenID Connect"]);
    await client.query(
      "update entry_embedding_jobs set status = 'done' where entry_id = 'entry_embedding_update'"
    );
    await client.query(
      "update entries set meaning_short = 'changed' where id = 'entry_embedding_update'"
    );

    const { rows } = await client.query<{ reason: string; status: string }>(
      "select reason, status from entry_embedding_jobs where entry_id = 'entry_embedding_update'"
    );
    expect(rows[0]).toEqual({ reason: "update", status: "pending" });
  });

  it("stores suggested edits by team", async () => {
    await insertTeam("team_suggestion", "suggestion.example");
    await client.query(
      `
      insert into suggested_edits (id, team_id, target_type, target_id, before_jsonb, after_jsonb)
      values ('suggestion_team_scoped', 'team_suggestion', 'entry', null, null, $1)
      `,
      [{ term: "SLO" }]
    );

    const { rows } = await client.query<{ team_id: string }>(
      "select team_id from suggested_edits where id = 'suggestion_team_scoped'"
    );
    expect(rows[0]?.team_id).toBe("team_suggestion");
  });

  it("stores search events without raw query text", async () => {
    await insertTeam("team_search_event", "search-event.example");
    await client.query(
      `
      insert into search_events (
        id, team_id, query_hash, layer_hits, result_terms, confidence_distribution, result_count, no_result, latency_ms
      ) values (
        'search_event_1', 'team_search_event', 'hash_only', $1, $2, $3, 0, true, 42
      )
      `,
      [["team"], ["SLO"], { T4: 1 }]
    );

    const { rows } = await client.query<{
      count: number;
      has_raw_query: boolean;
      result_terms: string[];
    }>(
      `
      select
        count(*) over ()::int as count,
        result_terms,
        exists (
          select 1
          from information_schema.columns
          where table_name = 'search_events' and column_name in ('query', 'raw_query')
        ) as has_raw_query
      from search_events
      where team_id = 'team_search_event' and query_hash = 'hash_only'
      `
    );
    expect(rows[0]).toEqual({ count: 1, has_raw_query: false, result_terms: ["SLO"] });
  });

  it("stores team invites and overlay review status", async () => {
    await insertTeam("team_invite", "invite.example");
    await insertUser("user_inviter", "team_invite");
    await client.query(
      `
      insert into team_invites (id, team_id, email, role, token_hash, invited_by, expires_at)
      values (
        'team_invite_1', 'team_invite', 'new@example.com', 'member', 'hash_token',
        'user_inviter', now() + interval '7 days'
      )
      `
    );
    await client.query(
      `
      insert into team_entries (
        id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
        confidence_tier, license, layer, team_id, aliases, related_terms, contemporaries, review_status
      ) values (
        'team_entry_review', 'RTO', 'rto', $1, $2, 'short', 'long', 'T4', 'MIT',
        'team', 'team_invite', $3, $4, $5, 'needs_review'
      )
      `,
      [["Recovery Time Objective"], ["ops"], [], [], []]
    );

    const { rows } = await client.query<{
      email: string;
      review_status: string;
      role: string;
    }>(
      `
      select i.email, i.role, e.review_status
      from team_invites i
      cross join team_entries e
      where i.id = 'team_invite_1' and e.id = 'team_entry_review'
      `
    );
    expect(rows[0]).toEqual({
      email: "new@example.com",
      review_status: "needs_review",
      role: "member"
    });
  });

  it("stores Teams installs by Microsoft tenant", async () => {
    await insertTeam("team_teams_install", "teams-install.example");
    await client.query(
      `
      insert into teams_installs (
        id, microsoft_tenant_id, tenant_name, team_id, app_id, auth_type, api_secret_registration_id
      ) values (
        'teams-install-tenant_123', 'tenant_123', 'Example Tenant', 'team_teams_install',
        'teams-app-id', 'apiSecretServiceAuth', 'secret-registration-id'
      )
      `
    );

    const { rows } = await client.query<{ team_id: string }>(
      "select team_id from teams_installs where microsoft_tenant_id = 'tenant_123'"
    );
    expect(rows[0]?.team_id).toBe("team_teams_install");
  });

  it("stores Discord installs by guild", async () => {
    await insertTeam("team_discord_install", "discord-install.example");
    await client.query(
      `
      insert into discord_installs (
        id, discord_guild_id, guild_name, team_id, application_id, bot_user_id, installer_discord_user_id, admin_role_ids
      ) values (
        'discord-install-guild_123', 'guild_123', 'Example Guild', 'team_discord_install',
        'discord-app-id', 'bot-user-id', 'installer-user-id', $1
      )
      `,
      [["role_admin"]]
    );

    const { rows } = await client.query<{ admin_role_ids: string[]; team_id: string }>(
      "select team_id, admin_role_ids from discord_installs where discord_guild_id = 'guild_123'"
    );
    expect(rows[0]).toEqual({
      admin_role_ids: ["role_admin"],
      team_id: "team_discord_install"
    });
  });
});

function hasDockerRuntime(): boolean {
  try {
    execFileSync("docker", ["info"], { stdio: "ignore", timeout: 5_000 });
    return true;
  } catch {
    return false;
  }
}

async function migrationCount(): Promise<number> {
  const { rows } = await client.query<{ count: number }>(
    "select count(*)::int as count from drizzle.__drizzle_migrations"
  );
  return rows[0]?.count ?? 0;
}

async function rowCount(table: string, where: string): Promise<number> {
  const { rows } = await client.query<{ count: number }>(
    `select count(*)::int as count from ${table} where ${where}`
  );
  return rows[0]?.count ?? 0;
}

async function connectWithRetry(connectionString: string): Promise<Client> {
  let lastError: unknown;

  for (let attempt = 0; attempt < 40; attempt += 1) {
    const pgClient = new Client({ connectionString });
    try {
      await pgClient.connect();
      return pgClient;
    } catch (error) {
      lastError = error;
      await pgClient.end().catch(() => undefined);
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }

  throw lastError;
}

async function insertEntry(
  id: string,
  term: string,
  termNormalized: string,
  expansions: string[],
  deprecated = false,
  contemporaries: string[] = []
): Promise<void> {
  await client.query(
    `
    insert into entries (
      id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
      confidence_tier, license, layer, deprecated, aliases, related_terms, contemporaries
    ) values ($1, $2, $3, $4, $5, 'short', 'long', 'T2', 'MIT', 'public', $6, $7, $8, $9)
    `,
    [id, term, termNormalized, expansions, ["test"], deprecated, [], [], contemporaries]
  );
}

async function insertTeam(id: string, emailDomain: string): Promise<void> {
  await client.query(
    "insert into teams (id, name, email_domain) values ($1, 'Test Team', $2) on conflict do nothing",
    [id, emailDomain]
  );
}

async function insertUser(id: string, teamId: string): Promise<void> {
  await client.query(
    "insert into users (id, email, team_id, role) values ($1, $2, $3, 'admin') on conflict do nothing",
    [id, `${id}@example.com`, teamId]
  );
}

async function insertTeamEntry(
  id: string,
  teamId: string,
  contemporaries: string[]
): Promise<void> {
  await client.query(
    `
    insert into team_entries (
      id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
      confidence_tier, license, layer, team_id, aliases, related_terms, contemporaries
    ) values ($1, 'Event Stream', 'event stream', $2, $3, 'short', 'long', 'T4', 'MIT', 'team', $4, $5, $6, $7)
    `,
    [id, ["Event Stream"], ["test"], teamId, [], [], contemporaries]
  );
}

async function insertPersonalEntry(
  id: string,
  userId: string,
  contemporaries: string[]
): Promise<void> {
  await client.query(
    `
    insert into personal_entries (
      id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
      confidence_tier, license, layer, user_id, aliases, related_terms, contemporaries
    ) values ($1, 'Event Stream', 'event stream', $2, $3, 'short', 'long', 'T4', 'MIT', 'personal', $4, $5, $6, $7)
    `,
    [id, ["Event Stream"], ["test"], userId, [], [], contemporaries]
  );
}
