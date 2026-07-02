import { createHash, randomUUID } from "node:crypto";

import type {
  Adapter,
  AdapterAccount,
  AdapterSession,
  AdapterUser,
  VerificationToken
} from "next-auth/adapters";

import { authDb } from "@/lib/auth-db";
import { findPendingInviteForEmail, markInviteAccepted } from "@/lib/team-invites";

type UserRow = {
  email: string;
  email_verified: Date | null;
  id: string;
  image: string | null;
  name: string | null;
  role: "admin" | "member";
  team_id: string | null;
};

type AccountRow = {
  access_token: string | null;
  expires_at: number | null;
  id_token: string | null;
  provider: string;
  provider_account_id: string;
  refresh_token: string | null;
  scope: string | null;
  session_state: string | null;
  token_type: string | null;
  type: AdapterAccount["type"];
  user_id: string;
};

type SessionRow = {
  expires: Date;
  session_token: string;
  user_id: string;
};

type VerificationTokenRow = {
  expires: Date;
  identifier: string;
  token: string;
};

type WatAdapterUser = AdapterUser & {
  role: "admin" | "member";
  teamId: string | null;
};

export function watNextAuthAdapter(): Adapter {
  return {
    async createSession(session) {
      const { rows } = await authDb().query<SessionRow>(
        `
        insert into sessions (session_token, user_id, expires)
        values ($1, $2, $3)
        returning session_token, user_id, expires
        `,
        [session.sessionToken, session.userId, session.expires]
      );
      return sessionFromRow(requireRow(rows[0], "session not created"));
    },

    async createUser(user: Omit<AdapterUser, "id">) {
      const email = normalizeEmail(user.email);
      const inviteAssignment = await findPendingInviteForEmail(email);
      const teamAssignment = inviteAssignment ?? (await assignTeamForEmail(email));
      const userId = randomUUID();
      const { rows } = await authDb().query<UserRow>(
        `
        insert into users (id, name, email, email_verified, image, team_id, role)
        values ($1, $2, $3, $4, $5, $6, $7)
        returning id, name, email, email_verified, image, team_id, role
        `,
        [
          userId,
          user.name ?? null,
          email,
          user.emailVerified ?? null,
          user.image ?? null,
          teamAssignment.teamId,
          teamAssignment.role
        ]
      );
      if (inviteAssignment) await markInviteAccepted(inviteAssignment.id, userId);
      return userFromRow(requireRow(rows[0], "user not created"));
    },

    async createVerificationToken(token) {
      const { rows } = await authDb().query<VerificationTokenRow>(
        `
        insert into verification_tokens (identifier, token, expires)
        values ($1, $2, $3)
        returning identifier, token, expires
        `,
        [normalizeEmail(token.identifier), token.token, token.expires]
      );
      return tokenFromRow(requireRow(rows[0], "verification token not created"));
    },

    async deleteSession(sessionToken) {
      const { rows } = await authDb().query<SessionRow>(
        `
        delete from sessions
        where session_token = $1
        returning session_token, user_id, expires
        `,
        [sessionToken]
      );
      return rows[0] ? sessionFromRow(rows[0]) : null;
    },

    async deleteUser(userId) {
      const { rows } = await authDb().query<UserRow>(
        `
        delete from users
        where id = $1
        returning id, name, email, email_verified, image, team_id, role
        `,
        [userId]
      );
      return rows[0] ? userFromRow(rows[0]) : null;
    },

    async getSessionAndUser(sessionToken) {
      const { rows } = await authDb().query<SessionRow & UserRow>(
        `
        select
          s.session_token,
          s.user_id,
          s.expires,
          u.id,
          u.name,
          u.email,
          u.email_verified,
          u.image,
          u.team_id,
          u.role
        from sessions s
        inner join users u on u.id = s.user_id
        where s.session_token = $1
        `,
        [sessionToken]
      );
      const row = rows[0];
      if (!row) return null;

      return {
        session: sessionFromRow(row),
        user: userFromRow(row)
      };
    },

    async getUser(id) {
      const { rows } = await authDb().query<UserRow>(
        "select id, name, email, email_verified, image, team_id, role from users where id = $1",
        [id]
      );
      return rows[0] ? userFromRow(rows[0]) : null;
    },

    async getUserByAccount(account) {
      const { rows } = await authDb().query<UserRow>(
        `
        select u.id, u.name, u.email, u.email_verified, u.image, u.team_id, u.role
        from accounts a
        inner join users u on u.id = a.user_id
        where a.provider = $1 and a.provider_account_id = $2
        `,
        [account.provider, account.providerAccountId]
      );
      return rows[0] ? userFromRow(rows[0]) : null;
    },

    async getUserByEmail(email) {
      const { rows } = await authDb().query<UserRow>(
        "select id, name, email, email_verified, image, team_id, role from users where lower(email) = lower($1)",
        [email]
      );
      return rows[0] ? userFromRow(rows[0]) : null;
    },

    async linkAccount(account: AdapterAccount) {
      const { rows } = await authDb().query<AccountRow>(
        `
        insert into accounts (
          user_id, type, provider, provider_account_id, refresh_token, access_token,
          expires_at, token_type, scope, id_token, session_state
        ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        returning *
        `,
        [
          account.userId,
          account.type,
          account.provider,
          account.providerAccountId,
          account.refresh_token ?? null,
          account.access_token ?? null,
          account.expires_at ?? null,
          account.token_type ?? null,
          account.scope ?? null,
          account.id_token ?? null,
          account.session_state == null ? null : String(account.session_state)
        ]
      );
      return accountFromRow(requireRow(rows[0], "account not linked"));
    },

    async unlinkAccount(account: Pick<AdapterAccount, "provider" | "providerAccountId">) {
      const { rows } = await authDb().query<AccountRow>(
        `
        delete from accounts
        where provider = $1 and provider_account_id = $2
        returning *
        `,
        [account.provider, account.providerAccountId]
      );
      return rows[0] ? accountFromRow(rows[0]) : undefined;
    },

    async updateSession(session) {
      const { rows } = await authDb().query<SessionRow>(
        `
        update sessions
        set
          user_id = coalesce($2, user_id),
          expires = coalesce($3, expires)
        where session_token = $1
        returning session_token, user_id, expires
        `,
        [session.sessionToken, session.userId ?? null, session.expires ?? null]
      );
      return rows[0] ? sessionFromRow(rows[0]) : null;
    },

    async updateUser(user) {
      const { rows } = await authDb().query<UserRow>(
        `
        update users
        set
          name = coalesce($2, name),
          email = coalesce($3, email),
          email_verified = coalesce($4, email_verified),
          image = coalesce($5, image)
        where id = $1
        returning id, name, email, email_verified, image, team_id, role
        `,
        [
          user.id,
          user.name ?? null,
          user.email ? normalizeEmail(user.email) : null,
          user.emailVerified ?? null,
          user.image ?? null
        ]
      );
      return userFromRow(requireRow(rows[0], "user not updated"));
    },

    async useVerificationToken(params) {
      const { rows } = await authDb().query<VerificationTokenRow>(
        `
        delete from verification_tokens
        where identifier = $1 and token = $2
        returning identifier, token, expires
        `,
        [normalizeEmail(params.identifier), params.token]
      );
      return rows[0] ? tokenFromRow(rows[0]) : null;
    }
  };
}

function accountFromRow(row: AccountRow): AdapterAccount {
  return {
    access_token: row.access_token ?? undefined,
    expires_at: row.expires_at ?? undefined,
    id_token: row.id_token ?? undefined,
    provider: row.provider,
    providerAccountId: row.provider_account_id,
    refresh_token: row.refresh_token ?? undefined,
    scope: row.scope ?? undefined,
    session_state: row.session_state ?? undefined,
    token_type: row.token_type ?? undefined,
    type: row.type,
    userId: row.user_id
  };
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function requireRow<T>(row: T | undefined, message: string): T {
  if (!row) throw new Error(message);
  return row;
}

function sessionFromRow(row: SessionRow): AdapterSession {
  return {
    expires: row.expires,
    sessionToken: row.session_token,
    userId: row.user_id
  };
}

function tokenFromRow(row: VerificationTokenRow): VerificationToken {
  return {
    expires: row.expires,
    identifier: row.identifier,
    token: row.token
  };
}

async function assignTeamForEmail(
  email: string
): Promise<{ role: "admin" | "member"; teamId: string | null }> {
  const domain = email.split("@")[1]?.trim().toLowerCase();
  if (!domain) return { role: "member", teamId: null };

  const { rows } = await authDb().query<{ created: boolean; id: string }>(
    `
    with inserted as (
      insert into teams (id, name, email_domain)
      values ($1, $2, $3)
      on conflict (email_domain) do nothing
      returning id
    )
    select id, true as created from inserted
    union all
    select id, false as created from teams
    where email_domain = $3 and not exists (select 1 from inserted)
    limit 1
    `,
    [teamIdForDomain(domain), domain, domain]
  );
  const team = requireRow(rows[0], "team not assigned");
  return {
    role: team.created ? "admin" : "member",
    teamId: team.id
  };
}

function slug(input: string): string {
  const value = input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
  return value || "domain";
}

function teamIdForDomain(domain: string): string {
  const hash = createHash("sha256").update(domain).digest("hex").slice(0, 10);
  return `team-${slug(domain)}-${hash}`;
}

function userFromRow(row: UserRow): WatAdapterUser {
  return {
    email: row.email,
    emailVerified: row.email_verified,
    id: row.id,
    image: row.image,
    name: row.name,
    role: row.role,
    teamId: row.team_id
  };
}
