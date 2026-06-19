import { readdir, readFile } from "node:fs/promises";

import { Client } from "pg";

const databaseUrl = process.env.WAT_DATABASE_URL ?? process.env.DATABASE_URL;
const connectionString = databaseUrl ?? "postgres://wat:wat@localhost:5432/wat";
const drizzleDir = new URL("../drizzle/", import.meta.url);

export async function applyMigrations(pgClient: Client): Promise<void> {
  const files = (await readdir(drizzleDir))
    .filter((file) => file.endsWith(".sql"))
    .sort((left, right) => left.localeCompare(right));

  for (const file of files) {
    await pgClient.query(await readFile(new URL(file, drizzleDir), "utf8"));
  }
}

async function main(): Promise<void> {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    await applyMigrations(client);
  } finally {
    await client.end();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
