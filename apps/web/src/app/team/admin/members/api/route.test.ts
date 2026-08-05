import { NextRequest } from "next/server";
import { afterEach, describe, expect, it } from "vitest";

import { getAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { testSessionToken } from "@/lib/session";
import { resetTeamInvitesForTest } from "@/lib/team-invites";
import { getTeamMembers, resetTeamMembersForTest } from "@/lib/team-members";
import { DELETE, GET, PATCH, POST } from "./route";

function request(
  method: string,
  body?: unknown,
  url = "https://wat.example.com/team/admin/members/api",
  token = testSessionToken()
) {
  return new NextRequest(url, {
    body: body === undefined ? undefined : JSON.stringify(body),
    headers: {
      "content-type": "application/json",
      cookie: `next-auth.session-token=${token}`
    },
    method
  });
}

describe("/team/admin/members/api", () => {
  afterEach(() => {
    resetAuditLogForTest();
    resetTeamInvitesForTest();
    resetTeamMembersForTest();
  });

  it("lists members and pending invites", async () => {
    await POST(request("POST", { email: "new@example.com", role: "member" }));
    const response = await GET(request("GET"));
    const body = (await response.json()) as { invites: unknown[]; members: unknown[] };

    expect(body.invites).toHaveLength(1);
    expect(body.members).toHaveLength(3);
  });

  it("invites, updates roles, and removes members with audit", async () => {
    const invite = await POST(request("POST", { email: "new@example.com", role: "admin" }));
    expect(invite?.status).toBe(201);

    const role = await PATCH(request("PATCH", { id: "user_platform", role: "admin" }));
    expect(role?.status).toBe(200);
    await expect(getTeamMembers()).resolves.toContainEqual(
      expect.objectContaining({ id: "user_platform", role: "admin" })
    );

    const unconfirmed = await DELETE(
      request("DELETE", undefined, "https://wat.example.com/team/admin/members/api?id=user_ops")
    );
    expect(unconfirmed?.status).toBe(400);

    const removed = await DELETE(
      request(
        "DELETE",
        undefined,
        "https://wat.example.com/team/admin/members/api?id=user_ops&confirm=user_ops"
      )
    );
    expect(removed?.status).toBe(200);
    expect((await getTeamMembers()).map((member) => member.id)).not.toContain("user_ops");
    expect((await getAuditLog("team_1")).map((item) => item.action)).toEqual([
      "member.invite",
      "member.role.update",
      "member.remove"
    ]);
  });

  it("requires admins for writes", async () => {
    const response = await POST(
      new NextRequest("https://wat.example.com/team/admin/members/api", {
        body: JSON.stringify({ email: "new@example.com" }),
        headers: {
          "content-type": "application/json",
          cookie: `next-auth.session-token=${testSessionToken({ role: "member" })}`
        },
        method: "POST"
      })
    );

    expect(response?.status).toBe(403);
  });

  it("does not expose or mutate members across teams", async () => {
    const teamTwo = testSessionToken({ teamId: "team_2" });
    const list = await GET(request("GET", undefined, undefined, teamTwo));
    const body = (await list.json()) as { members: unknown[] };
    expect(body.members).toEqual([]);

    const crossTenantRole = await PATCH(
      request("PATCH", { id: "user_platform", role: "admin" }, undefined, teamTwo)
    );
    expect(crossTenantRole?.status).toBe(404);

    const crossTenantRemove = await DELETE(
      request(
        "DELETE",
        undefined,
        "https://wat.example.com/team/admin/members/api?id=user_platform&confirm=user_platform",
        teamTwo
      )
    );
    expect(crossTenantRemove?.status).toBe(404);
    await expect(getTeamMembers()).resolves.toContainEqual(
      expect.objectContaining({ id: "user_platform", role: "member" })
    );
  });
});
