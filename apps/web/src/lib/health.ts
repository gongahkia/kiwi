import { Client } from "pg";

export interface HealthSnapshot {
  checked_at: string;
  service: "web";
  status: "ok";
}

export interface ReadinessSnapshot extends Omit<HealthSnapshot, "status"> {
  checks: {
    database: "missing_url" | "ok" | "unavailable";
    migrations: "missing" | "ok" | "unknown";
    seed_corpus: "missing" | "ok" | "unknown";
  };
  status: "not_ready" | "ok";
}

type ReadinessChecks = ReadinessSnapshot["checks"];

type Queryable = {
  query<T>(sql: string): Promise<{ rows: T[] }>;
};

export function getHealthSnapshot(): HealthSnapshot {
  return {
    checked_at: new Date().toISOString(),
    service: "web",
    status: "ok"
  };
}

export async function getReadinessSnapshot(
  env: NodeJS.ProcessEnv = process.env
): Promise<ReadinessSnapshot> {
  const checks = await getReadinessChecks(env);

  return {
    checked_at: new Date().toISOString(),
    checks,
    service: "web",
    status: readinessStatus(checks)
  };
}

export function readinessStatus(checks: ReadinessChecks): ReadinessSnapshot["status"] {
  return Object.values(checks).every((status) => status === "ok") ? "ok" : "not_ready";
}

async function getReadinessChecks(env: NodeJS.ProcessEnv): Promise<ReadinessChecks> {
  const databaseUrl = env.WAT_DATABASE_URL ?? env.DATABASE_URL;
  if (!databaseUrl) {
    return {
      database: "missing_url",
      migrations: "unknown",
      seed_corpus: "unknown"
    };
  }

  const client = new Client({
    connectionString: databaseUrl,
    connectionTimeoutMillis: 2000
  });

  try {
    await client.connect();
    const databaseChecks = await connectedDatabaseChecks(client);

    return {
      database: "ok",
      ...databaseChecks
    };
  } catch {
    return {
      database: "unavailable",
      migrations: "unknown",
      seed_corpus: "unknown"
    };
  } finally {
    await client.end().catch(() => undefined);
  }
}

export async function connectedDatabaseChecks(
  client: Queryable
): Promise<Pick<ReadinessChecks, "migrations" | "seed_corpus">> {
  const migrationsReady = await requiredMigrationsExist(client);
  if (!migrationsReady) {
    return {
      migrations: "missing",
      seed_corpus: "unknown"
    };
  }

  const seedReady = await publicSeedExists(client);
  return {
    migrations: "ok",
    seed_corpus: seedReady ? "ok" : "missing"
  };
}

async function requiredMigrationsExist(client: Queryable): Promise<boolean> {
  const result = await client.query<{ ready: boolean }>(`
    select (
      to_regclass('public.entries') is not null
      and to_regclass('public.sources') is not null
      and to_regclass('public.examples') is not null
      and to_regclass('public.teams') is not null
      and to_regclass('public.team_entries') is not null
      and to_regclass('public.personal_entries') is not null
      and to_regclass('public.suggested_edits') is not null
      and to_regclass('public.search_events') is not null
      and to_regclass('public.audit_log') is not null
      and to_regclass('public.entry_embedding_jobs') is not null
      and (
        select count(*) = 2
        from pg_extension
        where extname in ('pg_trgm', 'vector')
      )
      and exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'entries'
          and column_name = 'contemporaries'
      )
    ) as ready
  `);

  return result.rows[0]?.ready === true;
}

async function publicSeedExists(client: Queryable): Promise<boolean> {
  const result = await client.query<{ ready: boolean }>(
    "select exists (select 1 from entries where layer = 'public') as ready"
  );

  return result.rows[0]?.ready === true;
}
