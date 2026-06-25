import { describe, expect, it } from "vitest";

import {
  getTeamMembers,
  removeTeamMember,
  resetTeamMembersForTest,
  setTeamMemberRole
} from "./team-members";

describe("team members", () => {
  it("promotes and demotes members", async () => {
    resetTeamMembersForTest();

    expect(await setTeamMemberRole("team_1", "user_platform", "admin")).toMatchObject({ role: "admin" });
    expect(await setTeamMemberRole("team_1", "user_platform", "member")).toMatchObject({ role: "member" });
    resetTeamMembersForTest();
  });

  it("removes members", async () => {
    resetTeamMembersForTest();

    expect(await removeTeamMember("team_1", "user_ops")).toMatchObject({ id: "user_ops" });
    expect((await getTeamMembers()).map((member) => member.id)).not.toContain("user_ops");
    resetTeamMembersForTest();
  });
});
