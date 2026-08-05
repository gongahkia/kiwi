import type { NextRequest } from "next/server";

import { authDb } from "@/lib/auth-db";

export type TeamRole = "admin" | "member";

export interface WatSessionUser {
  email: string;
  id: string;
  role: TeamRole;
  teamId: string | null;
}

export const nextAuthSessionCookies = [
  "next-auth.session-token",
  "__Secure-next-auth.session-token"
] as const;

export function testSessionToken(
  input: {
    role?: TeamRole;
    teamId?: string;
    userId?: string;
  } = {}
): string {
  return `test:${input.userId ?? "user_admin"}:${input.teamId ?? "team_1"}:${input.role ?? "admin"}`;
}

function parseTestSession(token: string): WatSessionUser | null {
  if (process.env.NODE_ENV !== "test" || !token.startsWith("test:")) return null;
  const [, userId, teamId, role] = token.split(":");
  if (!userId || !teamId || (role !== "admin" && role !== "member")) return null;
  return {
    email: `${userId}@example.test`,
    id: userId,
    role,
    teamId
  };
}

export function sessionTokenFromRequest(request: NextRequest): string | null {
  for (const name of nextAuthSessionCookies) {
    const value = request.cookies.get(name)?.value.trim();
    if (value) return value;
  }
  return null;
}

export async function sessionUserFromToken(token: string | null): Promise<WatSessionUser | null> {
  if (!token) return null;
  const testSession = parseTestSession(token);
  if (testSession) return testSession;

  const { rows } = await authDb().query<{
    email: string;
    id: string;
    role: TeamRole;
    team_id: string | null;
  }>(
    `
    select u.id, u.email, u.role, u.team_id
    from sessions s
    inner join users u on u.id = s.user_id
    where s.session_token = $1 and s.expires > now()
    `,
    [token]
  );
  const row = rows[0];
  return row
    ? {
        email: row.email,
        id: row.id,
        role: row.role,
        teamId: row.team_id
      }
    : null;
}

export async function sessionUserFromRequest(request: NextRequest): Promise<WatSessionUser | null> {
  return sessionUserFromToken(sessionTokenFromRequest(request));
}

export async function sessionUserFromCookieStore(cookieStore: {
  get(name: string): { value: string } | undefined;
}): Promise<WatSessionUser | null> {
  for (const name of nextAuthSessionCookies) {
    const value = cookieStore.get(name)?.value.trim();
    if (value) return sessionUserFromToken(value);
  }
  return null;
}

export async function isAdminRequest(request: NextRequest): Promise<boolean> {
  return (await sessionUserFromRequest(request))?.role === "admin";
}
