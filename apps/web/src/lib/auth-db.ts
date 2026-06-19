import { Pool } from "pg";

const databaseUrl = process.env.WAT_DATABASE_URL ?? process.env.DATABASE_URL;
const connectionString = databaseUrl ?? "postgres://wat:wat@localhost:5432/wat";

const globalForAuthDb = globalThis as typeof globalThis & {
  watAuthPool?: Pool;
};

export function authDb(): Pool {
  globalForAuthDb.watAuthPool ??= new Pool({ connectionString });
  return globalForAuthDb.watAuthPool;
}
