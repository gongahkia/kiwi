import { describe, expect, it } from "vitest";

import { getTeamSettings, resetTeamSettingsForTest, updateTeamSettings } from "./team-settings";

describe("team settings", () => {
  it("persists default domain filter and public layer toggle", async () => {
    resetTeamSettingsForTest();
    await updateTeamSettings("team_1", {
      allow_public_layer: false,
      default_domain_filter: "Platform.Example"
    });

    expect(await getTeamSettings()).toMatchObject({
      allow_public_layer: false,
      default_domain_filter: "platform.example"
    });
    resetTeamSettingsForTest();
  });

  it("dedups normalized domain tags", async () => {
    resetTeamSettingsForTest();
    await updateTeamSettings("team_1", { domain_tags: ["Security", "security", ""] });

    expect((await getTeamSettings()).domain_tags).toContain("security");
    expect((await getTeamSettings()).domain_tags.filter((tag) => tag === "security")).toHaveLength(
      1
    );
    resetTeamSettingsForTest();
  });
});
