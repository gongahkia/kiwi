import { authDb } from "@/lib/auth-db";

export interface TeamSettings {
  allow_public_layer: boolean;
  default_domain_filter: string;
  domain_tags: string[];
}

const defaultSettings: TeamSettings = {
  allow_public_layer: true,
  default_domain_filter: "example.com",
  domain_tags: ["example.com", "platform", "ops"]
};

const testSettingsByTeam = new Map<string, TeamSettings>();
const defaultTestTeamId = "team_1";

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

function normalizeSettings(value: unknown): TeamSettings {
  const input = value && typeof value === "object" ? (value as Partial<TeamSettings>) : {};
  return {
    allow_public_layer:
      typeof input.allow_public_layer === "boolean"
        ? input.allow_public_layer
        : defaultSettings.allow_public_layer,
    default_domain_filter:
      typeof input.default_domain_filter === "string" && input.default_domain_filter.trim()
        ? input.default_domain_filter.trim().toLowerCase()
        : defaultSettings.default_domain_filter,
    domain_tags:
      Array.isArray(input.domain_tags) && input.domain_tags.every((tag) => typeof tag === "string")
        ? Array.from(
            new Set(input.domain_tags.map((tag) => tag.trim().toLowerCase()).filter(Boolean))
          ).sort()
        : defaultSettings.domain_tags
  };
}

function applySettingsPatch(current: TeamSettings, input: Partial<TeamSettings>): TeamSettings {
  const next = structuredClone(current);
  if (typeof input.allow_public_layer === "boolean") {
    next.allow_public_layer = input.allow_public_layer;
  }
  if (typeof input.default_domain_filter === "string" && input.default_domain_filter.trim()) {
    next.default_domain_filter = input.default_domain_filter.trim().toLowerCase();
  }
  if (Array.isArray(input.domain_tags)) {
    const nextTags = new Set(next.domain_tags);
    for (const tag of input.domain_tags) {
      const normalized = tag.trim().toLowerCase();
      if (normalized) nextTags.add(normalized);
    }
    next.domain_tags = Array.from(nextTags).sort();
  }
  return next;
}

export async function getTeamSettings(teamId = defaultTestTeamId): Promise<TeamSettings> {
  if (useTestState()) {
    return structuredClone(testSettingsByTeam.get(teamId) ?? defaultSettings);
  }
  const { rows } = await authDb().query<{ settings_jsonb: unknown }>(
    "select settings_jsonb from teams where id = $1",
    [teamId]
  );
  return normalizeSettings(rows[0]?.settings_jsonb);
}

export function resetTeamSettingsForTest(teamId = defaultTestTeamId): void {
  testSettingsByTeam.set(teamId, structuredClone(defaultSettings));
}

export async function updateTeamSettings(
  teamId: string,
  input: Partial<TeamSettings>
): Promise<TeamSettings> {
  const next = applySettingsPatch(await getTeamSettings(teamId), input);
  if (useTestState()) {
    testSettingsByTeam.set(teamId, structuredClone(next));
    return structuredClone(next);
  }
  const { rowCount } = await authDb().query(
    "update teams set settings_jsonb = $2::jsonb where id = $1",
    [teamId, JSON.stringify(next)]
  );
  if (rowCount === 0) throw new Error("team not found");
  return next;
}
