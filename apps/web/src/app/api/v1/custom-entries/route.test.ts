import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { resetApiKeysForTest, seedApiKeyForTest } from "@/lib/api-keys";
import { getAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { getPersonalEntries, resetPersonalEntriesForTest } from "@/lib/personal-entries";
import { getTeamEntries, initialTeamEntries, resetTeamEntriesForTest } from "@/lib/team-entries";
import { resetWriteRateLimitsForTest } from "@/lib/write-rate-limit";
import { POST } from "./route";

const previousCustomEntryWriteLimit = process.env.WAT_CUSTOM_ENTRY_WRITE_LIMIT;

function request(body: Record<string, unknown>, headers: Record<string, string> = {}) {
  const mergedHeaders: Record<string, string> = {
    authorization: "Bearer test-key",
    "content-type": "application/json",
    "x-wat-user-id": "user_1",
    ...headers
  };
  if (headers["x-wat-user-id"] === "") {
    delete mergedHeaders["x-wat-user-id"];
  }

  return new NextRequest("http://localhost/api/v1/custom-entries", {
    body: JSON.stringify(body),
    headers: mergedHeaders,
    method: "POST"
  });
}

describe("POST /api/v1/custom-entries", () => {
  beforeEach(() => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_1" });
    delete process.env.WAT_CUSTOM_ENTRY_WRITE_LIMIT;
    resetPersonalEntriesForTest();
    resetTeamEntriesForTest();
    resetWriteRateLimitsForTest();
    resetAuditLogForTest();
  });

  afterEach(() => {
    resetApiKeysForTest();
    if (previousCustomEntryWriteLimit === undefined) {
      delete process.env.WAT_CUSTOM_ENTRY_WRITE_LIMIT;
    } else {
      process.env.WAT_CUSTOM_ENTRY_WRITE_LIMIT = previousCustomEntryWriteLimit;
    }
    resetPersonalEntriesForTest();
    resetTeamEntriesForTest();
    resetWriteRateLimitsForTest();
    resetAuditLogForTest();
  });

  it("marks personal custom entries as proprietary", async () => {
    const response = await POST(
      request({
        expansion: "Change Approval Process",
        scope: "personal",
        sourceTitle: "Runbook",
        sourceUrl: "https://docs.example.test/cap",
        term: "CAP"
      })
    );
    const body = (await response.json()) as {
      entry: { sources: Array<{ license: string }> };
      scope: string;
    };

    expect(response.status).toBe(201);
    expect(body.scope).toBe("personal");
    expect(body.entry.sources[0]?.license).toBe("proprietary-personal");
    expect((await getPersonalEntries("user_1"))[0]?.sources[0]?.license).toBe(
      "proprietary-personal"
    );
    await expect(getAuditLog()).resolves.toContainEqual(
      expect.objectContaining({
        action: "custom_entry.create",
        target_type: "personal_entry",
        team_id: null
      })
    );
  });

  it("marks team custom entries as proprietary", async () => {
    const response = await POST(
      request(
        {
          expansion: "Recovery Time Objective",
          scope: "team",
          sourceTitle: "Runbook",
          sourceUrl: "https://docs.example.test/rto",
          term: "RTO"
        },
        { "x-wat-team-id": "team_1" }
      )
    );
    const body = (await response.json()) as {
      entry: { sources: Array<{ license: string }> };
      scope: string;
    };

    expect(response.status).toBe(201);
    expect(body.scope).toBe("team");
    expect(body.entry.sources[0]?.license).toBe("proprietary-team");
    expect(await getTeamEntries()).toHaveLength(initialTeamEntries.length + 1);
    expect((await getTeamEntries()).at(-1)?.sources[0]?.license).toBe("proprietary-team");
    await expect(getAuditLog("team_1")).resolves.toContainEqual(
      expect.objectContaining({
        action: "custom_entry.create",
        target_type: "team_entry"
      })
    );
  });

  it("rejects team custom entries for mismatched API key teams", async () => {
    const response = await POST(
      request(
        {
          expansion: "Recovery Time Objective",
          scope: "team",
          term: "RTO"
        },
        { "x-wat-team-id": "team_2" }
      )
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toMatchObject({ code: "team_scope_mismatch" });
    await expect(getTeamEntries("team_2")).resolves.toEqual([]);
  });

  it("rejects writes without user scope", async () => {
    const response = await POST(
      request(
        {
          expansion: "Change Approval Process",
          scope: "personal",
          term: "CAP"
        },
        { "x-wat-user-id": "" }
      )
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      code: "missing_user_scope",
      error: "missing_user_scope",
      message: "api token and x-wat-user-id are required"
    });
  });

  it("requires write scope", async () => {
    resetApiKeysForTest();
    seedApiKeyForTest({ key: "test-key", scopes: ["search"], teamId: "team_1" });

    const response = await POST(
      request({
        expansion: "Change Approval Process",
        scope: "personal",
        term: "CAP"
      })
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toMatchObject({ code: "insufficient_api_scope" });
  });

  it("rate limits custom entry writes by actor", async () => {
    process.env.WAT_CUSTOM_ENTRY_WRITE_LIMIT = "1";

    const first = await POST(
      request({
        expansion: "Change Approval Process",
        scope: "personal",
        term: "CAP"
      })
    );
    const second = await POST(
      request({
        expansion: "Recovery Time Objective",
        scope: "personal",
        term: "RTO"
      })
    );

    expect(first.status).toBe(201);
    expect(second.status).toBe(429);
    await expect(second.json()).resolves.toMatchObject({
      code: "rate_limited",
      error: "rate_limited",
      limit: 1,
      message: "rate limit exceeded",
      remaining: 0
    });
  });

  it("upserts personal custom entries by term and expansion", async () => {
    const first = await POST(
      request({
        expansion: "Change Approval Process",
        meaning: "Original meaning.",
        mode: "upsert",
        scope: "personal",
        sourceUrl: "https://docs.example.test/cap",
        term: "CAP"
      })
    );
    const firstBody = (await first.json()) as { entry: { id: string }; mode: string };

    const second = await POST(
      request({
        expansion: "Change Approval Process",
        meaning: "Updated meaning.",
        mode: "upsert",
        scope: "personal",
        sourceUrl: "https://docs.example.test/cap-v2",
        term: "CAP"
      })
    );
    const secondBody = (await second.json()) as {
      entry: { id: string; meaning: string };
      mode: string;
    };

    expect(first.status).toBe(201);
    expect(firstBody.mode).toBe("created");
    expect(second.status).toBe(200);
    expect(secondBody.mode).toBe("updated");
    expect(secondBody.entry.id).toBe(firstBody.entry.id);
    expect(secondBody.entry.meaning).toBe("Updated meaning.");
    expect(await getPersonalEntries("user_1")).toHaveLength(1);
    expect((await getAuditLog()).map((entry) => entry.action)).toEqual([
      "custom_entry.create",
      "custom_entry.update"
    ]);
  });

  it("upserts team custom entries by term and expansion", async () => {
    const first = await POST(
      request(
        {
          expansion: "Recovery Time Objective",
          mode: "upsert",
          scope: "team",
          sourceUrl: "https://docs.example.test/rto",
          term: "RTO"
        },
        { "x-wat-team-id": "team_1" }
      )
    );
    const firstBody = (await first.json()) as { entry: { id: string }; mode: string };

    const second = await POST(
      request(
        {
          expansion: "Recovery Time Objective",
          meaning: "Updated team meaning.",
          mode: "upsert",
          scope: "team",
          sourceUrl: "https://docs.example.test/rto-v2",
          term: "RTO"
        },
        { "x-wat-team-id": "team_1" }
      )
    );
    const secondBody = (await second.json()) as {
      entry: { id: string; meaning: string };
      mode: string;
    };

    expect(first.status).toBe(201);
    expect(firstBody.mode).toBe("created");
    expect(second.status).toBe(200);
    expect(secondBody.mode).toBe("updated");
    expect(secondBody.entry.id).toBe(firstBody.entry.id);
    expect(secondBody.entry.meaning).toBe("Updated team meaning.");
    expect(await getTeamEntries()).toHaveLength(initialTeamEntries.length + 1);
  });
});
