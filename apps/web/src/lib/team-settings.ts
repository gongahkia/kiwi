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

let settings = structuredClone(defaultSettings);

export function getTeamSettings(): TeamSettings {
  return structuredClone(settings);
}

export function resetTeamSettingsForTest() {
  settings = structuredClone(defaultSettings);
}

export function updateTeamSettings(input: Partial<TeamSettings>): TeamSettings {
  if (typeof input.allow_public_layer === "boolean") {
    settings.allow_public_layer = input.allow_public_layer;
  }
  if (typeof input.default_domain_filter === "string" && input.default_domain_filter.trim()) {
    settings.default_domain_filter = input.default_domain_filter.trim().toLowerCase();
  }
  if (Array.isArray(input.domain_tags)) {
    const nextTags = new Set(settings.domain_tags);
    for (const tag of input.domain_tags) {
      const normalized = tag.trim().toLowerCase();
      if (normalized) {
        nextTags.add(normalized);
      }
    }
    settings.domain_tags = Array.from(nextTags).sort();
  }

  return getTeamSettings();
}
