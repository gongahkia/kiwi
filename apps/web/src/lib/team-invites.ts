import { createHash, randomBytes, randomUUID } from "node:crypto";

import { authDb } from "@/lib/auth-db";
import type { TeamRole } from "@/lib/session";
import { addTeamMemberForTest } from "@/lib/team-members";

export interface TeamInvite {
  accepted_at: string | null;
  accepted_by: string | null;
  created_at: string;
  email: string;
  expires_at: string;
  id: string;
  invited_by: string | null;
  role: TeamRole;
  team_id: string;
}

export interface CreatedTeamInvite extends TeamInvite {
  token: string;
}

export interface PendingInviteAssignment {
  id: string;
  role: TeamRole;
  teamId: string;
}

const testInvites: Array<TeamInvite & { token_hash: string }> = [];

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function rowToInvite(row: {
  accepted_at: Date | null;
  accepted_by: string | null;
  created_at: Date;
  email: string;
  expires_at: Date;
  id: string;
  invited_by: string | null;
  role: TeamRole;
  team_id: string;
}): TeamInvite {
  return {
    accepted_at: row.accepted_at?.toISOString() ?? null,
    accepted_by: row.accepted_by,
    created_at: row.created_at.toISOString(),
    email: row.email,
    expires_at: row.expires_at.toISOString(),
    id: row.id,
    invited_by: row.invited_by,
    role: row.role,
    team_id: row.team_id
  };
}

function isPending(invite: TeamInvite): boolean {
  return !invite.accepted_at && Date.parse(invite.expires_at) > Date.now();
}

export async function createTeamInvite(input: {
  email: string;
  invitedBy: string;
  role?: TeamRole;
  teamId: string;
}): Promise<CreatedTeamInvite> {
  const token = `wti_${randomBytes(24).toString("base64url")}`;
  const invite: TeamInvite = {
    accepted_at: null,
    accepted_by: null,
    created_at: new Date().toISOString(),
    email: normalizeEmail(input.email),
    expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    id: randomUUID(),
    invited_by: input.invitedBy,
    role: input.role ?? "member",
    team_id: input.teamId
  };
  if (useTestState()) {
    testInvites.push({ ...structuredClone(invite), token_hash: hashToken(token) });
    return { ...structuredClone(invite), token };
  }

  const { rows } = await authDb().query<{
    accepted_at: Date | null;
    accepted_by: string | null;
    created_at: Date;
    email: string;
    expires_at: Date;
    id: string;
    invited_by: string | null;
    role: TeamRole;
    team_id: string;
  }>(
    `
    insert into team_invites (id, team_id, email, role, token_hash, invited_by, expires_at)
    values ($1, $2, $3, $4, $5, $6, $7)
    returning id, team_id, email, role, invited_by, accepted_by, accepted_at, expires_at, created_at
    `,
    [
      invite.id,
      invite.team_id,
      invite.email,
      invite.role,
      hashToken(token),
      invite.invited_by,
      new Date(invite.expires_at)
    ]
  );
  const row = rows[0];
  if (!row) throw new Error("invite create failed");
  return { ...rowToInvite(row), token };
}

export async function listTeamInvites(teamId: string): Promise<TeamInvite[]> {
  if (useTestState()) {
    return structuredClone(
      testInvites.filter((invite) => invite.team_id === teamId && isPending(invite))
    );
  }
  const { rows } = await authDb().query<{
    accepted_at: Date | null;
    accepted_by: string | null;
    created_at: Date;
    email: string;
    expires_at: Date;
    id: string;
    invited_by: string | null;
    role: TeamRole;
    team_id: string;
  }>(
    `
    select id, team_id, email, role, invited_by, accepted_by, accepted_at, expires_at, created_at
    from team_invites
    where team_id = $1 and accepted_at is null and expires_at > now()
    order by created_at desc
    `,
    [teamId]
  );
  return rows.map(rowToInvite);
}

export async function findPendingInviteForEmail(
  email: string
): Promise<PendingInviteAssignment | null> {
  const normalized = normalizeEmail(email);
  if (useTestState()) {
    const invite = testInvites.find((item) => item.email === normalized && isPending(item));
    return invite ? { id: invite.id, role: invite.role, teamId: invite.team_id } : null;
  }
  const { rows } = await authDb().query<{ id: string; role: TeamRole; team_id: string }>(
    `
    select id, team_id, role
    from team_invites
    where email = $1 and accepted_at is null and expires_at > now()
    order by created_at desc
    limit 1
    `,
    [normalized]
  );
  const row = rows[0];
  return row ? { id: row.id, role: row.role, teamId: row.team_id } : null;
}

export async function markInviteAccepted(inviteId: string, userId: string): Promise<void> {
  if (useTestState()) {
    const invite = testInvites.find((item) => item.id === inviteId);
    if (invite) {
      invite.accepted_at = new Date().toISOString();
      invite.accepted_by = userId;
      addTeamMemberForTest(invite.team_id, { email: invite.email, id: userId, role: invite.role });
    }
    return;
  }
  await authDb().query(
    "update team_invites set accepted_at = now(), accepted_by = $2 where id = $1",
    [inviteId, userId]
  );
}

export async function acceptTeamInvite(input: {
  email: string;
  token: string;
  userId: string;
}): Promise<TeamInvite> {
  const tokenHash = hashToken(input.token);
  const email = normalizeEmail(input.email);
  if (useTestState()) {
    const invite = testInvites.find(
      (item) => item.token_hash === tokenHash && item.email === email && isPending(item)
    );
    if (!invite) throw new Error("invite not found");
    invite.accepted_at = new Date().toISOString();
    invite.accepted_by = input.userId;
    addTeamMemberForTest(invite.team_id, {
      email: invite.email,
      id: input.userId,
      role: invite.role
    });
    return structuredClone(invite);
  }

  const { rows } = await authDb().query<{
    accepted_at: Date | null;
    accepted_by: string | null;
    created_at: Date;
    email: string;
    expires_at: Date;
    id: string;
    invited_by: string | null;
    role: TeamRole;
    team_id: string;
  }>(
    `
    with invite as (
      update team_invites
      set accepted_at = now(), accepted_by = $3
      where token_hash = $1 and email = $2 and accepted_at is null and expires_at > now()
      returning id, team_id, email, role, invited_by, accepted_by, accepted_at, expires_at, created_at
    ), updated_user as (
      update users
      set team_id = (select team_id from invite), role = (select role from invite)
      where id = $3
    )
    select * from invite
    `,
    [tokenHash, email, input.userId]
  );
  const row = rows[0];
  if (!row) throw new Error("invite not found");
  return rowToInvite(row);
}

export function resetTeamInvitesForTest(): void {
  testInvites.length = 0;
}
