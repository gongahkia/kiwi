import { NextRequest } from "next/server";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { resetTeamEntriesForTest, type TeamEntry } from "@/lib/team-entries";
import { resetWriteRateLimitsForTest } from "@/lib/write-rate-limit";
import { POST } from "./route";

const previousImportWriteLimit = process.env.WAT_IMPORT_WRITE_LIMIT;

const entry: TeamEntry = {
  domains: ["ops"],
  expansion: "Recovery Time Objective",
  id: "team-import-rto",
  meaning: "Maximum acceptable restore time.",
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

function request(entries: TeamEntry[]) {
  return new NextRequest("https://wat.example.com/team/admin/import", {
    body: JSON.stringify({ entries }),
    headers: {
      "content-type": "application/json",
      cookie: "wat_session=dev"
    },
    method: "POST"
  });
}

describe("POST /team/admin/import", () => {
  beforeEach(() => {
    process.env.WAT_IMPORT_WRITE_LIMIT = "1";
    resetTeamEntriesForTest();
    resetWriteRateLimitsForTest();
  });

  afterEach(() => {
    if (previousImportWriteLimit === undefined) {
      delete process.env.WAT_IMPORT_WRITE_LIMIT;
    } else {
      process.env.WAT_IMPORT_WRITE_LIMIT = previousImportWriteLimit;
    }
    resetTeamEntriesForTest();
    resetWriteRateLimitsForTest();
  });

  it("rate limits imports by actor", async () => {
    const first = await POST(request([entry]));
    const second = await POST(request([{ ...entry, id: "team-import-rto-2" }]));

    expect(first.status).toBe(200);
    expect(second.status).toBe(429);
    await expect(second.json()).resolves.toMatchObject({
      code: "rate_limited",
      error: "rate_limited",
      limit: 1,
      message: "rate limit exceeded",
      remaining: 0
    });
  });
});
