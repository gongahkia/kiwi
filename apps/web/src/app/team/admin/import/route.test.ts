import { NextRequest } from "next/server";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { resetApiKeysForTest, seedApiKeyForTest } from "@/lib/api-keys";
import { getAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { testSessionToken } from "@/lib/session";
import {
  getTeamEntries,
  replaceTeamEntriesForTest,
  resetTeamEntriesForTest,
  type TeamEntry
} from "@/lib/team-entries";
import { resetWriteRateLimitsForTest } from "@/lib/write-rate-limit";
import { POST } from "./api/route";
import { GET as CSV_TEMPLATE } from "./template/csv/route";
import { GET as JSON_TEMPLATE } from "./template/json/route";

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

function request(entries: TeamEntry[], token = testSessionToken()) {
  return new NextRequest("https://wat.example.com/team/admin/import/api", {
    body: JSON.stringify({ entries }),
    headers: {
      "content-type": "application/json",
      cookie: `next-auth.session-token=${token}`
    },
    method: "POST"
  });
}

function apiRequest(entries: TeamEntry[], headers: Record<string, string> = {}) {
  return new NextRequest("https://wat.example.com/team/admin/import/api", {
    body: JSON.stringify({ entries }),
    headers: {
      authorization: "Bearer import-key",
      "content-type": "application/json",
      "x-wat-team-id": "team_api",
      ...headers
    },
    method: "POST"
  });
}

function csvRequest(body: string) {
  return new NextRequest("https://wat.example.com/team/admin/import/api", {
    body,
    headers: {
      "content-type": "text/csv",
      cookie: `next-auth.session-token=${testSessionToken()}`
    },
    method: "POST"
  });
}

describe("POST /team/admin/import/api", () => {
  beforeEach(() => {
    process.env.WAT_IMPORT_WRITE_LIMIT = "1";
    seedApiKeyForTest({ key: "import-key", scopes: ["admin"], teamId: "team_api" });
    resetTeamEntriesForTest();
    replaceTeamEntriesForTest([], "team_api");
    resetAuditLogForTest();
    resetWriteRateLimitsForTest();
  });

  afterEach(() => {
    resetApiKeysForTest();
    resetAuditLogForTest();
    if (previousImportWriteLimit === undefined) {
      delete process.env.WAT_IMPORT_WRITE_LIMIT;
    } else {
      process.env.WAT_IMPORT_WRITE_LIMIT = previousImportWriteLimit;
    }
    resetTeamEntriesForTest();
    replaceTeamEntriesForTest([], "team_api");
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

  it("requires a team admin session for browser imports", async () => {
    const response = await POST(request([entry], testSessionToken({ role: "member" })));

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toMatchObject({
      code: "admin_required",
      error: "admin_required",
      message: "admin required"
    });
  });

  it("imports with a team-scoped admin API key", async () => {
    const response = await POST(apiRequest([entry]));
    const result = (await response.json()) as { inserted: number; skipped: number };

    expect(response.status).toBe(200);
    expect(result).toEqual({ inserted: 1, skipped: 0 });
    await expect(getTeamEntries("team_api")).resolves.toHaveLength(1);
    await expect(getAuditLog("team_api")).resolves.toContainEqual(
      expect.objectContaining({ action: "team_entry.import" })
    );
  });

  it("rejects import API keys without admin scope", async () => {
    resetApiKeysForTest();
    seedApiKeyForTest({ key: "import-key", scopes: ["write"], teamId: "team_api" });

    const response = await POST(apiRequest([entry]));

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toMatchObject({
      code: "insufficient_api_scope",
      error: "insufficient_api_scope",
      message: "admin scope is required"
    });
    await expect(getTeamEntries("team_api")).resolves.toHaveLength(0);
  });

  it("rejects import API team mismatches before writing", async () => {
    const response = await POST(apiRequest([entry], { "x-wat-team-id": "team_other" }));

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toMatchObject({
      code: "team_scope_mismatch",
      error: "team_scope_mismatch"
    });
    await expect(getTeamEntries("team_api")).resolves.toHaveLength(0);
  });

  it("downloads and imports the JSON template", async () => {
    const template = JSON_TEMPLATE();
    const body = (await template.json()) as { entries: TeamEntry[] };
    const response = await POST(request(body.entries));
    const result = (await response.json()) as { inserted: number; skipped: number };

    expect(template.headers.get("content-disposition")).toContain("wat-team-import-template.json");
    expect(response.status).toBe(200);
    expect(result).toEqual({ inserted: 1, skipped: 0 });
  });

  it("downloads and imports the CSV template", async () => {
    const template = CSV_TEMPLATE();
    const response = await POST(csvRequest(await template.text()));
    const result = (await response.json()) as { inserted: number; skipped: number };

    expect(template.headers.get("content-disposition")).toContain("wat-team-import-template.csv");
    expect(response.status).toBe(200);
    expect(result).toEqual({ inserted: 1, skipped: 0 });
  });
});
