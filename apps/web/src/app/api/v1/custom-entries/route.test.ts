import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { getPersonalEntries, resetPersonalEntriesForTest } from "@/lib/personal-entries";
import { getTeamEntries, initialTeamEntries, resetTeamEntriesForTest } from "@/lib/team-entries";
import { POST } from "./route";

const previousApiKey = process.env.WAT_API_KEY;

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
    process.env.WAT_API_KEY = "test-key";
    resetPersonalEntriesForTest();
    resetTeamEntriesForTest();
  });

  afterEach(() => {
    if (previousApiKey === undefined) {
      delete process.env.WAT_API_KEY;
    } else {
      process.env.WAT_API_KEY = previousApiKey;
    }
    resetPersonalEntriesForTest();
    resetTeamEntriesForTest();
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
    expect(getPersonalEntries("user_1")[0]?.sources[0]?.license).toBe("proprietary-personal");
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
    expect(getTeamEntries()).toHaveLength(initialTeamEntries.length + 1);
    expect(getTeamEntries().at(-1)?.sources[0]?.license).toBe("proprietary-team");
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
    await expect(response.json()).resolves.toEqual({
      error: "api token and x-wat-user-id are required"
    });
  });
});
