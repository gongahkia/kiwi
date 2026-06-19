import { getTeamMember, type TeamRole } from "./team-members";

export function sessionUserId(sessionValue: string): string {
  return sessionValue === "dev" ? "user_admin" : sessionValue;
}

export function sessionTeamRole(sessionValue: string): TeamRole | null {
  const userId = sessionUserId(sessionValue);
  return getTeamMember(userId)?.role ?? null;
}

export function isAdminSession(sessionValue: string): boolean {
  return sessionTeamRole(sessionValue) === "admin";
}
