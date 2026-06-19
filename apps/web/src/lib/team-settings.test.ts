import { describe, expect, it } from "vitest";

import { getTeamSettings, resetTeamSettingsForTest, updateTeamSettings } from "./team-settings";

describe("team settings", () => {
  it("persists default domain filter and public layer toggle", () => {
    resetTeamSettingsForTest();
    updateTeamSettings({
      allow_public_layer: false,
      default_domain_filter: "Platform.Example"
    });

    expect(getTeamSettings()).toMatchObject({
      allow_public_layer: false,
      default_domain_filter: "platform.example"
    });
    resetTeamSettingsForTest();
  });

  it("dedups normalized domain tags", () => {
    resetTeamSettingsForTest();
    updateTeamSettings({ domain_tags: ["Security", "security", ""] });

    expect(getTeamSettings().domain_tags).toContain("security");
    expect(getTeamSettings().domain_tags.filter((tag) => tag === "security")).toHaveLength(1);
    resetTeamSettingsForTest();
  });
});
