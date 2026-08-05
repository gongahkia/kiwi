import { NextRequest } from "next/server";
import { afterEach, describe, expect, it } from "vitest";

import { resetApiKeysForTest } from "@/lib/api-keys";
import { getAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { testSessionToken } from "@/lib/session";
import { DELETE, POST } from "./route";

function request(
  method: string,
  body?: unknown,
  url = "https://wat.example.com/team/admin/api-keys/api"
) {
  return new NextRequest(url, {
    body: body === undefined ? undefined : JSON.stringify(body),
    headers: {
      "content-type": "application/json",
      cookie: `next-auth.session-token=${testSessionToken()}`
    },
    method
  });
}

describe("/team/admin/api-keys/api", () => {
  afterEach(() => {
    resetApiKeysForTest();
    resetAuditLogForTest();
  });

  it("audits create and confirmed revoke", async () => {
    const created = await POST(
      request("POST", { name: "Search key", scopes: ["search", "suggest"] })
    );
    const body = (await created!.json()) as { key: { id: string } };
    expect(created?.status).toBe(201);

    const unconfirmed = await DELETE(
      request(
        "DELETE",
        undefined,
        `https://wat.example.com/team/admin/api-keys/api?id=${body.key.id}`
      )
    );
    expect(unconfirmed?.status).toBe(400);

    const revoked = await DELETE(
      request(
        "DELETE",
        undefined,
        `https://wat.example.com/team/admin/api-keys/api?id=${body.key.id}&confirm=${body.key.id}`
      )
    );
    expect(revoked?.status).toBe(200);
    await expect(getAuditLog("team_1")).resolves.toMatchObject([
      { action: "api_key.create" },
      { action: "api_key.revoke" }
    ]);
  });

  it("requires admins", async () => {
    const response = await POST(
      new NextRequest("https://wat.example.com/team/admin/api-keys/api", {
        body: JSON.stringify({ name: "Member key" }),
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
