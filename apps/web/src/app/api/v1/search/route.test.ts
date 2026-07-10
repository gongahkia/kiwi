import { afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

import { resetApiKeysForTest, seedApiKeyForTest } from "@/lib/api-keys";
import { getSearchAnalyticsSummary, resetSearchAnalyticsForTest } from "@/lib/search-analytics";
import {
  replaceTeamEntriesForTest,
  resetTeamEntriesForTest,
  type TeamEntry
} from "@/lib/team-entries";
import { GET, OPTIONS } from "./route";

const previousAllowedOrigins = process.env.WAT_ALLOWED_ORIGINS;

const privateEntry: TeamEntry = {
  domains: ["private"],
  expansion: "Secret Launch Key",
  id: "team-secret-slk",
  meaning: "Private unreleased launch codename.",
  sources: [
    {
      license: "proprietary-team",
      publisher: "wat test",
      retrieved_at: "2026-07-10T00:00:00.000Z",
      snippet: "SLK is private.",
      title: "Private glossary",
      url: "https://example.test/private/slk"
    }
  ],
  term: "SLK"
};

describe("GET /api/v1/search", () => {
  afterEach(() => {
    resetApiKeysForTest();
    resetSearchAnalyticsForTest();
    resetTeamEntriesForTest("team_secret");
    if (previousAllowedOrigins === undefined) {
      delete process.env.WAT_ALLOWED_ORIGINS;
    } else {
      process.env.WAT_ALLOWED_ORIGINS = previousAllowedOrigins;
    }
  });

  it("returns contemporaries on every result entry", async () => {
    const response = await GET(new NextRequest("http://localhost/api/v1/search?q=API&limit=1"));
    const body = (await response.json()) as {
      matches: Array<{ entry: { contemporaries?: unknown } }>;
    };

    expect(response.status).toBe(200);
    expect(Array.isArray(body.matches[0]?.entry.contemporaries)).toBe(true);
  });

  it("logs and returns request ids", async () => {
    const log = vi.spyOn(console, "info").mockImplementation(() => undefined);

    const response = await GET(
      new NextRequest("http://localhost/api/v1/search?q=API&limit=1", {
        headers: { "x-request-id": "req_123" }
      })
    );

    expect(response.headers.get("x-request-id")).toBe("req_123");
    const event = JSON.parse(String(log.mock.calls[0]?.[0])) as {
      no_result?: boolean;
      query?: string;
      query_hash?: string;
      request_id?: string;
    };
    expect(event.request_id).toBe("req_123");
    expect(event.query_hash).toBeTruthy();
    expect(event.query).toBeUndefined();
    log.mockRestore();
  });

  it("records privacy-safe analytics for team searches", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    const response = await GET(
      new NextRequest("http://localhost/api/v1/search?q=definitely-unknown", {
        headers: {
          authorization: "Bearer test-key",
          "x-wat-team-id": "team_123",
          "x-wat-user-id": "user_123"
        }
      })
    );

    expect(response.status).toBe(200);
    await expect(getSearchAnalyticsSummary("team_123")).resolves.toMatchObject({
      noResultCount: 1,
      recentQueryHashes: [expect.any(String)],
      total: 1
    });
  });

  it("uses configured CORS origins", () => {
    process.env.WAT_ALLOWED_ORIGINS = "https://wat.example.com";
    const response = OPTIONS(
      new NextRequest("http://localhost/api/v1/search", {
        headers: { origin: "https://wat.example.com" }
      })
    );

    expect(response.headers.get("access-control-allow-origin")).toBe("https://wat.example.com");
    expect(response.headers.get("access-control-allow-credentials")).toBe("true");
  });

  it("does not expose private team overlays to anonymous fuzzed searches", async () => {
    replaceTeamEntriesForTest([privateEntry], "team_secret");

    const response = await GET(
      new NextRequest(
        "http://localhost/api/v1/search?q=%27%20OR%20%271%27%3D%271%20SLK%20%3Cscript%3E&limit=10"
      )
    );
    const body = (await response.json()) as {
      matches: Array<{ entry: { id: string; layer: string } }>;
    };

    expect(response.status).toBe(200);
    expect(body.matches.map((match) => match.entry.id)).not.toContain(privateEntry.id);
    expect(body.matches.every((match) => match.entry.layer === "public")).toBe(true);
  });

  it("fails closed before search on API team scope mismatches", async () => {
    seedApiKeyForTest({ key: "secret-key", teamId: "team_secret" });
    replaceTeamEntriesForTest([privateEntry], "team_secret");

    const response = await GET(
      new NextRequest("http://localhost/api/v1/search?q=SLK", {
        headers: {
          authorization: "Bearer secret-key",
          "x-wat-team-id": "team_other"
        }
      })
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toMatchObject({ code: "team_scope_mismatch" });
  });
});
