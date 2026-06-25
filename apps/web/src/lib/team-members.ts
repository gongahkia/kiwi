import { authDb } from "@/lib/auth-db";

export type TeamRole = "admin" | "member";

export interface TeamMember {
  email: string;
  id: string;
  role: TeamRole;
}

export const initialTeamMembers: TeamMember[] = [
  { email: "admin@example.com", id: "user_admin", role: "admin" },
  { email: "platform@example.com", id: "user_platform", role: "member" },
  { email: "ops@example.com", id: "user_ops", role: "member" }
];

const defaultTestTeamId = "team_1";
const testMembersByTeam = new Map<string, TeamMember[]>();

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

function testMembers(teamId: string): TeamMember[] {
  const existing = testMembersByTeam.get(teamId);
  if (existing) return existing;
  const members = teamId === defaultTestTeamId ? structuredClone(initialTeamMembers) : [];
  testMembersByTeam.set(teamId, members);
  return members;
}

function rowToMember(row: { email: string; id: string; role: TeamRole }): TeamMember {
  return { email: row.email, id: row.id, role: row.role };
}

export async function getTeamMembers(teamId = defaultTestTeamId): Promise<TeamMember[]> {
  if (useTestState()) return structuredClone(testMembers(teamId));
  const { rows } = await authDb().query<{ email: string; id: string; role: TeamRole }>(
    "select id, email, role from users where team_id = $1 order by email",
    [teamId]
  );
  return rows.map(rowToMember);
}

export async function getTeamMember(
  teamId: string,
  memberIdOrEmail: string
): Promise<TeamMember | null> {
  if (useTestState()) {
    const member = testMembers(teamId).find(
      (item) => item.id === memberIdOrEmail || item.email === memberIdOrEmail
    );
    return member ? structuredClone(member) : null;
  }
  const { rows } = await authDb().query<{ email: string; id: string; role: TeamRole }>(
    `
    select id, email, role
    from users
    where team_id = $1 and (id = $2 or lower(email) = lower($2))
    `,
    [teamId, memberIdOrEmail]
  );
  return rows[0] ? rowToMember(rows[0]) : null;
}

export function resetTeamMembersForTest(teamId = defaultTestTeamId): void {
  testMembersByTeam.set(teamId, structuredClone(initialTeamMembers));
}

export async function setTeamMemberRole(
  teamId: string,
  memberId: string,
  role: TeamRole
): Promise<TeamMember> {
  if (useTestState()) {
    const member = testMembers(teamId).find((item) => item.id === memberId);
    if (!member) throw new Error("member not found");
    member.role = role;
    return structuredClone(member);
  }
  const { rows } = await authDb().query<{ email: string; id: string; role: TeamRole }>(
    `
    update users
    set role = $3
    where team_id = $1 and id = $2
    returning id, email, role
    `,
    [teamId, memberId, role]
  );
  if (!rows[0]) throw new Error("member not found");
  return rowToMember(rows[0]);
}

export async function removeTeamMember(teamId: string, memberId: string): Promise<TeamMember> {
  if (useTestState()) {
    const members = testMembers(teamId);
    const index = members.findIndex((item) => item.id === memberId);
    if (index === -1) throw new Error("member not found");
    const [removed] = members.splice(index, 1);
    return structuredClone(removed!);
  }
  const { rows } = await authDb().query<{ email: string; id: string; role: TeamRole }>(
    `
    update users
    set team_id = null
    where team_id = $1 and id = $2
    returning id, email, role
    `,
    [teamId, memberId]
  );
  if (!rows[0]) throw new Error("member not found");
  return rowToMember(rows[0]);
}
