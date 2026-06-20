import { execFileSync } from "node:child_process";

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Client } from "pg";
import { GenericContainer, type StartedTestContainer, Wait } from "testcontainers";

import { applyMigrations } from "./migrate.js";

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

    client = new Client({
      connectionString: `postgres://wat:wat@${container.getHost()}:${container.getMappedPort(5432)}/wat`
    });
    await client.connect();
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
});

function hasDockerRuntime(): boolean {
  try {
    execFileSync("docker", ["info"], { stdio: "ignore", timeout: 5_000 });
    return true;
  } catch {
    return false;
  }
}

async function insertEntry(
  id: string,
  term: string,
  termNormalized: string,
  expansions: string[],
  deprecated = false
): Promise<void> {
  await client.query(
    `
    insert into entries (
      id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
      confidence_tier, license, layer, deprecated, aliases, related_terms
    ) values ($1, $2, $3, $4, $5, 'short', 'long', 'T2', 'MIT', 'public', $6, $7, $8)
    `,
    [id, term, termNormalized, expansions, ["test"], deprecated, [], []]
  );
}
