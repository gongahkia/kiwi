import { describe, expect, it } from "vitest";

import {
  getTeamMembers,
  removeTeamMember,
  resetTeamMembersForTest,
  setTeamMemberRole
} from "./team-members";

describe("team members", () => {
  it("promotes and demotes members", () => {
    resetTeamMembersForTest();

    expect(setTeamMemberRole("user_platform", "admin")).toMatchObject({ role: "admin" });
    expect(setTeamMemberRole("user_platform", "member")).toMatchObject({ role: "member" });
    resetTeamMembersForTest();
  });

  it("removes members", () => {
    resetTeamMembersForTest();

    expect(removeTeamMember("user_ops")).toMatchObject({ id: "user_ops" });
    expect(getTeamMembers().map((member) => member.id)).not.toContain("user_ops");
    resetTeamMembersForTest();
  });
});
