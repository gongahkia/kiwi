import { NextRequest } from "next/server";
import { afterEach, describe, expect, it } from "vitest";

import { getAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { resetPersonalEntriesForTest, type PersonalEntry } from "@/lib/personal-entries";
import { testSessionToken } from "@/lib/session";
import { DELETE, PATCH, POST } from "./route";

const entry: PersonalEntry = {
  domains: ["private"],
  expansion: "Customer Access Policy",
  id: "personal-route-cap",
  meaning: "Private access note.",
  sources: [
    {
      license: "proprietary-personal",
      publisher: "wat test",
      retrieved_at: "2026-06-24T00:00:00.000Z",
      snippet: "CAP fixture.",
      title: "CAP fixture",
      url: "https://example.com/cap"
    }
  ],
  term: "CAP"
};

function request(method: string, body?: unknown, url = "https://wat.example.com/personal/api") {
  return new NextRequest(url, {
    body: body === undefined ? undefined : JSON.stringify(body),
    headers: {
      "content-type": "application/json",
      cookie: `next-auth.session-token=${testSessionToken({ userId: "user_personal" })}`
    },
    method
  });
}

describe("/personal/api", () => {
  afterEach(() => {
    resetAuditLogForTest();
    resetPersonalEntriesForTest();
  });

  it("audits create, update, and confirmed deprecation", async () => {
    expect((await POST(request("POST", entry)))?.status).toBe(200);
    expect(
      (await PATCH(request("PATCH", { id: entry.id, patch: { review_status: "stale" } })))?.status
    ).toBe(200);

    const unconfirmed = await DELETE(
      request("DELETE", undefined, `https://wat.example.com/personal/api?id=${entry.id}`)
    );
    expect(unconfirmed?.status).toBe(400);

    const removed = await DELETE(
      request(
        "DELETE",
        undefined,
        `https://wat.example.com/personal/api?id=${entry.id}&confirm=${entry.id}`
      )
    );
    expect(removed?.status).toBe(200);
    expect((await getAuditLog()).map((item) => item.action)).toEqual([
      "personal_entry.create",
      "personal_entry.update",
      "personal_entry.deprecate"
    ]);
  });
});
