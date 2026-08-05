import { afterEach, describe, expect, it } from "vitest";

import {
  acceptTeamInvite,
  createTeamInvite,
  findPendingInviteForEmail,
  listTeamInvites,
  resetTeamInvitesForTest
} from "./team-invites";
import { getTeamMembers, resetTeamMembersForTest } from "./team-members";

describe("team invites", () => {
  afterEach(() => {
    resetTeamInvitesForTest();
    resetTeamMembersForTest();
  });

  it("creates pending invites and accepts them into team membership", async () => {
    const invite = await createTeamInvite({
      email: "New@Example.com",
      invitedBy: "user_admin",
      role: "admin",
      teamId: "team_1"
    });

    expect(invite.email).toBe("new@example.com");
    await expect(listTeamInvites("team_1")).resolves.toHaveLength(1);
    await expect(findPendingInviteForEmail("new@example.com")).resolves.toMatchObject({
      role: "admin",
      teamId: "team_1"
    });

    await acceptTeamInvite({
      email: "new@example.com",
      token: invite.token,
      userId: "user_new"
    });

    await expect(findPendingInviteForEmail("new@example.com")).resolves.toBeNull();
    await expect(getTeamMembers()).resolves.toContainEqual({
      email: "new@example.com",
      id: "user_new",
      role: "admin"
    });
  });
});
