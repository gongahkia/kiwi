import { Client } from "pg";

import { seedPublicCorpus } from "./seed-public.js";

const databaseUrl = process.env.WAT_DATABASE_URL ?? process.env.DATABASE_URL;
const connectionString = databaseUrl ?? "postgres://wat:wat@localhost:5432/wat";
const seedLimit = 50;

async function main(): Promise<void> {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const result = await seedPublicCorpus(client, { limit: seedLimit });
    console.log(`Seeded ${result.count} dev entries.`);
  } finally {
    await client.end();
  }
}

await main();
