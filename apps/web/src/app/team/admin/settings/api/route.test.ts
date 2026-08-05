import { NextRequest } from "next/server";
import { afterEach, describe, expect, it } from "vitest";

import { getAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { testSessionToken } from "@/lib/session";
import { resetTeamProfileForTest } from "@/lib/team-profile";
import { resetTeamSettingsForTest } from "@/lib/team-settings";
import { POST } from "./route";

describe("POST /team/admin/settings/api", () => {
  afterEach(() => {
    resetAuditLogForTest();
    resetTeamProfileForTest();
    resetTeamSettingsForTest();
  });

  it("updates team profile and settings with audit", async () => {
    const response = await POST(
      new NextRequest("https://wat.example.com/team/admin/settings/api", {
        body: JSON.stringify({
          profile: { email_domain: "Platform.Example", name: "Platform Team" },
          settings: { allow_public_layer: false }
        }),
        headers: {
          "content-type": "application/json",
          cookie: `next-auth.session-token=${testSessionToken()}`
        },
        method: "POST"
      })
    );
    const body = (await response!.json()) as {
      profile?: { email_domain?: string; name?: string };
      settings?: { allow_public_layer?: boolean };
    };

    expect(response?.status).toBe(200);
    expect(body.profile).toEqual({
      email_domain: "platform.example",
      name: "Platform Team"
    });
    expect(body.settings).toMatchObject({ allow_public_layer: false });
    await expect(getAuditLog("team_1")).resolves.toContainEqual(
      expect.objectContaining({ action: "team.settings.update" })
    );
  });

  it("requires admins", async () => {
    const response = await POST(
      new NextRequest("https://wat.example.com/team/admin/settings/api", {
        body: JSON.stringify({ profile: { name: "Member Edit" } }),
        headers: {
          "content-type": "application/json",
          cookie: `next-auth.session-token=${testSessionToken({ role: "member" })}`
        },
        method: "POST"
      })
    );

    expect(response?.status).toBe(403);
  });
});
