import { createHash, randomBytes } from "node:crypto";

import { Client } from "pg";

import { applyMigrations } from "./migrate.js";

type Scope = "admin" | "search" | "suggest" | "write";

type BootstrapOptions = {
  email: string;
  forceKey: boolean;
  json: boolean;
  keyName: string;
  migrate: boolean;
  name: string | null;
  scopes: Scope[];
  skipKey: boolean;
  teamDomain: string;
  teamName: string;
};

const validScopes = new Set<Scope>(["admin", "search", "suggest", "write"]);

function usage(): string {
  return [
    "Usage: pnpm bootstrap:admin -- --email admin@example.com [options]",
    "",
    "Options:",
    "  --email <email>          Required admin email. Env: BOOTSTRAP_ADMIN_EMAIL",
    "  --name <name>            Admin display name. Env: BOOTSTRAP_ADMIN_NAME",
    "  --team-name <name>       Team name. Env: BOOTSTRAP_TEAM_NAME",
    "  --team-domain <domain>   Team email domain. Defaults to admin email domain.",
    "  --key-name <name>        API key name. Default: Bootstrap admin key",
    "  --scopes <csv>           API key scopes. Default: admin,search,suggest,write",
    "  --force-key              Create a new key even if an active key with this name exists.",
    "  --skip-key               Create/promote team admin only.",
    "  --migrate                Run DB migrations before bootstrapping.",
    "  --json                   Print JSON output.",
    "  --help                   Show this help."
  ].join("\n");
}

function parseArgs(argv: string[]): Record<string, string | boolean> {
  const parsed: Record<string, string | boolean> = {};
  const args = argv.filter((arg) => arg !== "--");
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]!;
    if (!arg.startsWith("--")) throw new Error(`unexpected argument: ${arg}`);
    const [rawKey = "", inlineValue] = arg.slice(2).split("=", 2);
    const key = rawKey.trim();
    if (["force-key", "help", "json", "migrate", "skip-key"].includes(key)) {
      parsed[key] = true;
      continue;
    }
    const value = inlineValue ?? args[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`missing value for --${key}`);
    parsed[key] = value;
    if (inlineValue == null) index += 1;
  }
  return parsed;
}

function normalizeEmail(value: string | undefined): string {
  const email = value?.trim().toLowerCase();
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new Error("--email must be a valid email address");
  }
  return email;
}

function domainFromEmail(email: string): string {
  const domain = email.split("@")[1]?.trim().toLowerCase();
  if (!domain) throw new Error("email domain could not be derived");
  return domain;
}

function normalizeDomain(value: string): string {
  const domain = value.trim().toLowerCase();
  if (!/^[a-z0-9.-]+\.[a-z0-9-]+$/.test(domain)) {
    throw new Error("--team-domain must be a valid DNS-style domain");
  }
  return domain;
}

function parseScopes(value: string | undefined): Scope[] {
  const scopes = (value ?? "admin,search,suggest,write")
    .split(",")
    .map((scope) => scope.trim())
    .filter(Boolean);
  if (scopes.length === 0) throw new Error("--scopes must include at least one scope");
  for (const scope of scopes) {
    if (!validScopes.has(scope as Scope)) throw new Error(`invalid API key scope: ${scope}`);
  }
  return Array.from(new Set(scopes)) as Scope[];
}

function optionsFromEnvAndArgs(argv: string[], env: NodeJS.ProcessEnv): BootstrapOptions {
  const args = parseArgs(argv);
  if (args.help) {
    console.log(usage());
    process.exit(0);
  }

  const email = normalizeEmail((args.email as string | undefined) ?? env.BOOTSTRAP_ADMIN_EMAIL);
  const teamDomain = normalizeDomain(
    (args["team-domain"] as string | undefined) ??
      env.BOOTSTRAP_TEAM_DOMAIN ??
      domainFromEmail(email)
  );

  return {
    email,
    forceKey: Boolean(args["force-key"]),
    json: Boolean(args.json),
    keyName:
      ((args["key-name"] as string | undefined) ?? env.BOOTSTRAP_API_KEY_NAME)?.trim() ||
      "Bootstrap admin key",
    migrate: Boolean(args.migrate),
    name:
      ((args.name as string | undefined) ?? env.BOOTSTRAP_ADMIN_NAME)?.trim() ||
      email.split("@")[0] ||
      null,
    scopes: parseScopes((args.scopes as string | undefined) ?? env.BOOTSTRAP_API_KEY_SCOPES),
    skipKey: Boolean(args["skip-key"]),
    teamDomain,
    teamName:
      ((args["team-name"] as string | undefined) ?? env.BOOTSTRAP_TEAM_NAME)?.trim() || teamDomain
  };
}

function slug(input: string): string {
  const value = input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
  return value || "item";
}

function stableId(prefix: string, value: string): string {
  const hash = createHash("sha256").update(value).digest("hex").slice(0, 10);
  return `${prefix}-${slug(value)}-${hash}`;
}

function hashApiKey(key: string): string {
  return createHash("sha256").update(key).digest("hex");
}

function keyPrefix(key: string): string {
  return key.slice(0, 14);
}

function generateApiKey(): string {
  return `wat_${randomBytes(32).toString("base64url")}`;
}

async function assertTablesExist(client: Client): Promise<void> {
  const { rows } = await client.query<{
    api_keys: string | null;
    teams: string | null;
    users: string | null;
  }>(
    `
    select
      to_regclass('public.teams')::text as teams,
      to_regclass('public.users')::text as users,
      to_regclass('public.api_keys')::text as api_keys
    `
  );
  const row = rows[0];
  if (!row?.teams || !row.users || !row.api_keys) {
    throw new Error("required tables are missing; run pnpm db:migrate or pass --migrate");
  }
}

async function bootstrap(client: Client, options: BootstrapOptions) {
  const teamId = stableId("team", options.teamDomain);
  const userId = stableId("user", options.email);
  const rawKey = options.skipKey ? null : generateApiKey();

  await client.query("begin");
  try {
    const team = await client.query<{
      created: boolean;
      email_domain: string;
      id: string;
      name: string;
    }>(
      `
      with inserted as (
        insert into teams (id, name, email_domain)
        values ($1, $2, $3)
        on conflict (email_domain) do nothing
        returning id, name, email_domain
      )
      select id, name, email_domain, true as created from inserted
      union all
      select id, name, email_domain, false as created from teams
      where email_domain = $3 and not exists (select 1 from inserted)
      limit 1
      `,
      [teamId, options.teamName, options.teamDomain]
    );
    const teamRow = team.rows[0];
    if (!teamRow) throw new Error("team bootstrap failed");

    const user = await client.query<{
      email: string;
      id: string;
      role: string;
      team_id: string | null;
    }>(
      `
      insert into users (id, name, email, email_verified, team_id, role)
      values ($1, $2, $3, now(), $4, 'admin')
      on conflict (email) do update set
        name = coalesce(users.name, excluded.name),
        email_verified = coalesce(users.email_verified, excluded.email_verified),
        team_id = excluded.team_id,
        role = 'admin'
      returning id, email, team_id, role
      `,
      [userId, options.name, options.email, teamRow.id]
    );
    const userRow = user.rows[0];
    if (!userRow) throw new Error("admin user bootstrap failed");

    const existingKey = options.skipKey
      ? null
      : await client.query<{
          id: string;
          key_prefix: string;
          scopes: Scope[];
        }>(
          `
          select id, key_prefix, scopes
          from api_keys
          where team_id = $1 and name = $2 and revoked_at is null
          order by created_at desc
          limit 1
          `,
          [teamRow.id, options.keyName]
        );
    const shouldCreateKey = rawKey && (options.forceKey || existingKey?.rows.length === 0);
    const createdKey = shouldCreateKey
      ? await client.query<{
          id: string;
          key_prefix: string;
          scopes: Scope[];
        }>(
          `
          insert into api_keys (id, team_id, name, key_prefix, key_hash, scopes, created_by)
          values ($1, $2, $3, $4, $5, $6, $7)
          returning id, key_prefix, scopes
          `,
          [
            stableId("key", `${teamRow.id}:${options.keyName}:${Date.now()}:${rawKey}`),
            teamRow.id,
            options.keyName,
            keyPrefix(rawKey),
            hashApiKey(rawKey),
            options.scopes,
            userRow.id
          ]
        )
      : null;

    await client.query("commit");
    return {
      apiKey: createdKey?.rows[0]
        ? { ...createdKey.rows[0], key: rawKey }
        : existingKey?.rows[0]
          ? { ...existingKey.rows[0], key: null }
          : null,
      team: teamRow,
      user: userRow
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
}

function printText(result: Awaited<ReturnType<typeof bootstrap>>): void {
  console.log("Bootstrap complete.");
  console.log(`Team: ${result.team.id} (${result.team.email_domain})`);
  console.log(`Admin: ${result.user.email} (${result.user.role})`);
  if (!result.apiKey) {
    console.log("API key: skipped");
    return;
  }
  console.log(`API key: ${result.apiKey.id} (${result.apiKey.scopes.join(",")})`);
  if (result.apiKey.key) {
    console.log(`Raw API key (shown once): ${result.apiKey.key}`);
    console.log("");
    console.log("Runtime env:");
    console.log(`  WAT_API_KEY=${result.apiKey.key}`);
    console.log(`  WAT_TEAM_ID=${result.team.id}`);
  } else {
    console.log(
      "Raw API key: existing active key not shown; rerun with --force-key to create one."
    );
  }
}

async function main(): Promise<void> {
  const options = optionsFromEnvAndArgs(process.argv.slice(2), process.env);
  const connectionString =
    process.env.WAT_DATABASE_URL ??
    process.env.DATABASE_URL ??
    "postgres://wat:wat@localhost:5432/wat";
  const client = new Client({ connectionString });
  await client.connect();
  try {
    if (options.migrate) await applyMigrations(client);
    await assertTablesExist(client);
    const result = await bootstrap(client, options);
    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      printText(result);
    }
  } finally {
    await client.end();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    await main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
