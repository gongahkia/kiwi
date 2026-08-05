import { authDb } from "@/lib/auth-db";

export interface TeamProfile {
  email_domain: string;
  name: string;
}

const defaultTestTeamId = "team_1";
const defaultProfile: TeamProfile = {
  email_domain: "example.com",
  name: "example.com"
};
const testProfilesByTeam = new Map<string, TeamProfile>();

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

function normalizeDomain(value: string): string {
  return value.trim().toLowerCase();
}

function normalizeProfile(input: Partial<TeamProfile>, current = defaultProfile): TeamProfile {
  const name = input.name?.trim() || current.name;
  const emailDomain =
    typeof input.email_domain === "string" && input.email_domain.trim()
      ? normalizeDomain(input.email_domain)
      : current.email_domain;
  return { email_domain: emailDomain, name };
}

export async function getTeamProfile(teamId = defaultTestTeamId): Promise<TeamProfile> {
  if (useTestState()) return structuredClone(testProfilesByTeam.get(teamId) ?? defaultProfile);
  const { rows } = await authDb().query<{ email_domain: string; name: string }>(
    "select name, email_domain from teams where id = $1",
    [teamId]
  );
  if (!rows[0]) throw new Error("team not found");
  return normalizeProfile(rows[0]);
}

export function resetTeamProfileForTest(teamId = defaultTestTeamId): void {
  testProfilesByTeam.set(teamId, structuredClone(defaultProfile));
}

export async function updateTeamProfile(
  teamId: string,
  input: Partial<TeamProfile>
): Promise<TeamProfile> {
  const next = normalizeProfile(input, await getTeamProfile(teamId));
  if (useTestState()) {
    testProfilesByTeam.set(teamId, structuredClone(next));
    return structuredClone(next);
  }
  const { rows } = await authDb().query<{ email_domain: string; name: string }>(
    `
    update teams
    set name = $2, email_domain = $3
    where id = $1
    returning name, email_domain
    `,
    [teamId, next.name, next.email_domain]
  );
  if (!rows[0]) throw new Error("team not found");
  return normalizeProfile(rows[0]);
}
