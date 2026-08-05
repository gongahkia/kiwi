import { describe, expect, it } from "vitest";

import { getTeamProfile, resetTeamProfileForTest, updateTeamProfile } from "./team-profile";

describe("team profile", () => {
  it("persists normalized team name and domain", async () => {
    resetTeamProfileForTest();
    await updateTeamProfile("team_1", {
      email_domain: "Platform.Example",
      name: "Platform Team"
    });

    await expect(getTeamProfile()).resolves.toEqual({
      email_domain: "platform.example",
      name: "Platform Team"
    });
    resetTeamProfileForTest();
  });
});
