import { randomUUID } from "node:crypto";

import { Client } from "pg";

const databaseUrl = process.env.WAT_DATABASE_URL ?? process.env.DATABASE_URL;
const connectionString = databaseUrl ?? "postgres://wat:wat@localhost:5432/wat";

interface QueryResult<Row> {
  rows: Row[];
}

interface PgClient {
  end?(): Promise<void>;
  query<Row>(sql: string, values?: unknown[]): Promise<QueryResult<Row>>;
}

interface RecoverTeamAdminInput {
  force?: boolean;
  teamId: string;
  userEmail?: string;
  userId?: string;
}

interface UserRow {
  email: string;
  id: string;
  role: "admin" | "member";
  team_id: string;
}

export async function recoverTeamAdmin(
  client: PgClient,
  input: RecoverTeamAdminInput
): Promise<UserRow> {
  if (!input.teamId.trim()) throw new Error("team id is required");
  if (!input.userId?.trim() && !input.userEmail?.trim()) {
    throw new Error("user id or email is required");
  }

  await client.query("begin");
  try {
    const { rows: adminRows } = await client.query<{ count: string }>(
      "select count(*)::text as count from users where team_id = $1 and role = 'admin'",
      [input.teamId]
    );
    const adminCount = Number(adminRows[0]?.count ?? 0);
    if (adminCount > 0 && !input.force) {
      throw new Error("team already has an admin; pass --force to override");
    }

    const user = await lockRecoveryUser(client, input);
    if (!user) throw new Error("team member not found");

    const { rows } = await client.query<UserRow>(
      "update users set role = 'admin' where team_id = $1 and id = $2 returning id, email, team_id, role",
      [input.teamId, user.id]
    );
    const recovered = rows[0];
    if (!recovered) throw new Error("admin recovery update failed");

    await client.query(
      `
      insert into audit_log (
        id, actor_id, team_id, action, target_type, target_id, before_jsonb, after_jsonb
      ) values ($1, null, $2, 'member.admin_recover', 'user', $3, $4::jsonb, $5::jsonb)
      `,
      [
        randomUUID(),
        input.teamId,
        recovered.id,
        JSON.stringify({ role: user.role }),
        JSON.stringify({ recovery: true, role: recovered.role })
      ]
    );
    await client.query("commit");
    return recovered;
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
}

async function lockRecoveryUser(
  client: PgClient,
  input: RecoverTeamAdminInput
): Promise<UserRow | null> {
  if (input.userId?.trim()) {
    const { rows } = await client.query<UserRow>(
      "select id, email, team_id, role from users where team_id = $1 and id = $2 for update",
      [input.teamId, input.userId.trim()]
    );
    return rows[0] ?? null;
  }

  const { rows } = await client.query<UserRow>(
    "select id, email, team_id, role from users where team_id = $1 and lower(email) = lower($2) for update",
    [input.teamId, input.userEmail!.trim()]
  );
  return rows[0] ?? null;
}

function parseArgs(argv: string[]): RecoverTeamAdminInput {
  const input: RecoverTeamAdminInput = { teamId: "" };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--force") {
      input.force = true;
    } else if (arg === "--team-id") {
      input.teamId = argv[++index] ?? "";
    } else if (arg === "--user-id") {
      input.userId = argv[++index];
    } else if (arg === "--user-email") {
      input.userEmail = argv[++index];
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  return input;
}

async function main(): Promise<void> {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const user = await recoverTeamAdmin(client, parseArgs(process.argv.slice(2)));
    console.log(`recovered admin ${user.email} for team ${user.team_id}`);
  } finally {
    await client.end();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
