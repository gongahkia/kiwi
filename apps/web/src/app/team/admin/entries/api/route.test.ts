import { NextRequest } from "next/server";
import { afterEach, describe, expect, it, vi } from "vitest";

import { getAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { testSessionToken } from "@/lib/session";
import {
  getTeamEntries,
  initialTeamEntries,
  resetTeamEntriesForTest,
  type TeamEntry
} from "@/lib/team-entries";
import { DELETE, GET, PATCH, POST } from "./route";

const entry: TeamEntry = {
  domains: ["ops"],
  expansion: "Recovery Time Objective",
  id: "team-route-rto",
  meaning: "Restore target.",
  sources: [
    {
      license: "proprietary-team",
      publisher: "wat test",
      retrieved_at: "2026-06-24T00:00:00.000Z",
      snippet: "RTO fixture.",
      title: "RTO fixture",
      url: "https://example.com/rto"
    }
  ],
  term: "RTO"
};

function request(
  method: string,
  body?: unknown,
  url = "https://wat.example.com/team/admin/entries/api",
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

describe("GET /team/admin/entries/api", () => {
  const previousWebhookUrl = process.env.WAT_WEBHOOK_URL;
  const previousWebhookSecret = process.env.WAT_WEBHOOK_SECRET;

  afterEach(() => {
    resetAuditLogForTest();
    resetTeamEntriesForTest();
    vi.restoreAllMocks();
    if (previousWebhookUrl === undefined) delete process.env.WAT_WEBHOOK_URL;
    else process.env.WAT_WEBHOOK_URL = previousWebhookUrl;
    if (previousWebhookSecret === undefined) delete process.env.WAT_WEBHOOK_SECRET;
    else process.env.WAT_WEBHOOK_SECRET = previousWebhookSecret;
  });

  it("paginates team entries", async () => {
    const response = await GET(
      new NextRequest("https://wat.example.com/team/admin/entries/api?limit=1", {
        headers: { cookie: `next-auth.session-token=${testSessionToken()}` }
      })
    );
    const body = (await response.json()) as {
      entries: unknown[];
      page: { limit: number; next_cursor: string | null; total: number };
    };

    expect(body.entries).toHaveLength(1);
    expect(body.page).toMatchObject({
      limit: 1,
      next_cursor: "1",
      total: initialTeamEntries.length
    });
  });

  it("creates, updates, and deprecates entries with audit", async () => {
    expect((await POST(request("POST", entry)))?.status).toBe(200);
    expect(
      (await PATCH(request("PATCH", { id: entry.id, patch: { review_status: "needs_review" } })))
        ?.status
    ).toBe(200);

    const unconfirmed = await DELETE(
      request("DELETE", undefined, `https://wat.example.com/team/admin/entries/api?id=${entry.id}`)
    );
    expect(unconfirmed?.status).toBe(400);

    const removed = await DELETE(
      request(
        "DELETE",
        undefined,
        `https://wat.example.com/team/admin/entries/api?id=${entry.id}&confirm=${entry.id}`
      )
    );
    expect(removed?.status).toBe(200);
    expect((await getTeamEntries()).map((item) => item.id)).not.toContain(entry.id);
    expect((await getAuditLog("team_1")).map((item) => item.action)).toEqual([
      "team_entry.create",
      "team_entry.update",
      "team_entry.deprecate"
    ]);
  });

  it("sends signed webhooks for entry creates and updates", async () => {
    process.env.WAT_WEBHOOK_URL = "https://hooks.example.test/wat";
    process.env.WAT_WEBHOOK_SECRET = "secret";
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(new Response(null, { status: 204 }));

    expect((await POST(request("POST", entry)))?.status).toBe(200);
    expect(
      (await PATCH(request("PATCH", { id: entry.id, patch: { meaning: "Updated target." } })))
        ?.status
    ).toBe(200);

    expect(fetchSpy).toHaveBeenCalledTimes(2);
    const first = fetchSpy.mock.calls[0]![1]!;
    const second = fetchSpy.mock.calls[1]![1]!;
    expect((first.headers as Record<string, string>)["x-wat-event"]).toBe("team_entry.created");
    expect((second.headers as Record<string, string>)["x-wat-event"]).toBe("team_entry.updated");
    expect((first.headers as Record<string, string>)["x-wat-signature"]).toMatch(
      /^sha256=[a-f0-9]{64}$/u
    );
  });

  it("fails closed for cross-tenant and fuzzed entry ids", async () => {
    const teamTwo = testSessionToken({ teamId: "team_2" });
    const list = await GET(request("GET", undefined, undefined, teamTwo));
    const body = (await list.json()) as { entries: unknown[]; page: { total: number } };
    expect(body.entries).toEqual([]);
    expect(body.page.total).toBe(0);

    const crossTenantPatch = await PATCH(
      request(
        "PATCH",
        { id: "team-example-cap", patch: { meaning: "<script>alert(1)</script>" } },
        undefined,
        teamTwo
      )
    );
    expect(crossTenantPatch?.status).toBe(404);

    const fuzzId = "' OR '1'='1<script>";
    const fuzzDelete = await DELETE(
      request(
        "DELETE",
        undefined,
        `https://wat.example.com/team/admin/entries/api?id=${encodeURIComponent(fuzzId)}&confirm=${encodeURIComponent(fuzzId)}`
      )
    );
    expect(fuzzDelete?.status).toBe(404);
    expect((await getTeamEntries()).map((item) => item.id)).toEqual(
      initialTeamEntries.map((item) => item.id)
    );
  });
});
