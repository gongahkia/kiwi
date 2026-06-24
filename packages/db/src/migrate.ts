import { fileURLToPath } from "node:url";

import { drizzle } from "drizzle-orm/node-postgres";
import { migrate as runDrizzleMigrations } from "drizzle-orm/node-postgres/migrator";
import { Client } from "pg";

const databaseUrl = process.env.WAT_DATABASE_URL ?? process.env.DATABASE_URL;
const connectionString = databaseUrl ?? "postgres://wat:wat@localhost:5432/wat";
const migrationsFolder = fileURLToPath(new URL("../drizzle/", import.meta.url));

export async function applyMigrations(pgClient: Client): Promise<void> {
  await runDrizzleMigrations(drizzle(pgClient), { migrationsFolder });
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
