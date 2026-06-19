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

let members = structuredClone(initialTeamMembers);

export function getTeamMembers(): TeamMember[] {
  return structuredClone(members);
}

export function getTeamMember(memberIdOrEmail: string): TeamMember | null {
  const member = members.find(
    (item) => item.id === memberIdOrEmail || item.email === memberIdOrEmail
  );
  return member ? structuredClone(member) : null;
}

export function resetTeamMembersForTest() {
  members = structuredClone(initialTeamMembers);
}

export function setTeamMemberRole(memberId: string, role: TeamRole): TeamMember {
  const member = members.find((item) => item.id === memberId);
  if (!member) {
    throw new Error("member not found");
  }

  member.role = role;
  return structuredClone(member);
}

export function removeTeamMember(memberId: string): TeamMember {
  const index = members.findIndex((item) => item.id === memberId);
  if (index === -1) {
    throw new Error("member not found");
  }

  const [removed] = members.splice(index, 1);
  if (!removed) {
    throw new Error("member not found");
  }

  return structuredClone(removed);
}
