import { execFile as execFileCallback, execFileSync } from "node:child_process";
import { randomInt } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Client } from "pg";

import fixtures from "../fixtures/postgres-bm25.json" with { type: "json" };
import { searchPostgresEntries } from "./postgres.js";

const execFile = promisify(execFileCallback);
const containerName = `wat-search-test-${Date.now()}-${randomInt(1000, 9999)}`;
const port = randomInt(40001, 55000);
const connectionString = `postgres://wat:wat@localhost:${port}/wat`;
const drizzleDir = new URL("../../db/drizzle/", import.meta.url);
const repoRoot = fileURLToPath(new URL("../../../", import.meta.url));

let client: Client;

const shouldRunContainerTests = process.env.CI === "true" || hasDockerRuntime();

describe.skipIf(!shouldRunContainerTests)("searchPostgresEntries", () => {
  beforeAll(async () => {
    await execFile("docker", [
      "run",
      "--rm",
      "--name",
      containerName,
      "-e",
      "POSTGRES_USER=wat",
      "-e",
      "POSTGRES_PASSWORD=wat",
      "-e",
      "POSTGRES_DB=wat",
      "-p",
      `${port}:5432`,
      "-d",
      "pgvector/pgvector:pg16"
    ]);

    client = await connectWithRetry();
    await applyMigrations(client);
    await execFile("pnpm", ["--dir", repoRoot, "db:seed:dev"], {
      env: { ...process.env, WAT_DATABASE_URL: connectionString }
    });
  }, 120_000);

  afterAll(async () => {
    await client?.end();
    await execFile("docker", ["rm", "-f", containerName]).catch(() => undefined);
  }, 30_000);

  it.each(fixtures)("ranks $query first", async ({ expected_id, query }) => {
    const response = await searchPostgresEntries(client, { query, limit: 5 });

    expect(response.matches[0]?.entry.id).toBe(expected_id);
    expect(response.matches[0]?.score_breakdown.bm25).toBeGreaterThan(0);
    expect(response.matches[0]?.entry.sources.length).toBeGreaterThan(0);
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

async function connectWithRetry(): Promise<Client> {
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

async function applyMigrations(pgClient: Client): Promise<void> {
  const files = (await readdir(drizzleDir))
    .filter((file) => file.endsWith(".sql"))
    .sort((left, right) => left.localeCompare(right));

  for (const file of files) {
    await pgClient.query(await readFile(new URL(file, drizzleDir), "utf8"));
  }
}
