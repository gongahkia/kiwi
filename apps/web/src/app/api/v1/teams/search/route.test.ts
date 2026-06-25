import { afterEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { resetApiKeysForTest, seedApiKeyForTest } from "@/lib/api-keys";
import { getTeamsSearch } from "./handler";
import { GET } from "./route";

describe("GET /api/v1/teams/search", () => {
  afterEach(resetApiKeysForTest);

  it("returns Teams-friendly glossary results through API-secret auth", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    const response = await GET(
      new NextRequest("https://wat.example.com/api/v1/teams/search?q=API", {
        headers: { authorization: "Bearer test-key" }
      })
    );
    const body = (await response.json()) as {
      results?: Array<{ expansion?: string; term?: string; title?: string; url?: string }>;
    };

    expect(response.status).toBe(200);
    expect(body.results?.[0]?.title).toContain(":");
    expect(body.results?.[0]?.url).toMatch(/^https:\/\/wat\.example\.com\/term\//);
    expect(body.results?.length).toBeGreaterThan(0);
  });

  it("passes through invalid API-secret errors", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    const response = await GET(
      new NextRequest("https://wat.example.com/api/v1/teams/search?q=API", {
        headers: { authorization: "Bearer bad-key" }
      })
    );

    expect(response.status).toBe(401);
  });

  it("uses DB-backed Teams tenant mapping when supplied by an integration gateway", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_from_install" });

    const response = await getTeamsSearch(
      new NextRequest("https://wat.example.com/api/v1/teams/search?q=API", {
        headers: {
          authorization: "Bearer test-key",
          "x-wat-teams-tenant-id": "tenant_123"
        }
      }),
      {
        getInstall: async () => ({
          api_secret_registration_id: "secret-registration-id",
          app_id: "teams-app-id",
          auth_type: "apiSecretServiceAuth",
          id: "teams-install-tenant_123",
          installed_at: "2026-06-25T00:00:00.000Z",
          installed_by: null,
          microsoft_tenant_id: "tenant_123",
          service_url: null,
          team_id: "team_from_install",
          tenant_name: "Example Tenant",
          updated_at: "2026-06-25T00:00:00.000Z"
        })
      }
    );
    const body = (await response.json()) as { results?: unknown[] };

    expect(response.status).toBe(200);
    expect(body.results?.length).toBeGreaterThan(0);
  });

  it("fails closed for unknown supplied Teams tenants", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    const response = await getTeamsSearch(
      new NextRequest("https://wat.example.com/api/v1/teams/search?q=API", {
        headers: {
          authorization: "Bearer test-key",
          "x-wat-teams-tenant-id": "tenant_unknown"
        }
      }),
      { getInstall: async () => null }
    );

    expect(response.status).toBe(403);
  });

  it("returns an empty Teams result list for blank searches", async () => {
    const response = await GET(new NextRequest("https://wat.example.com/api/v1/teams/search?q="));
    const body = (await response.json()) as { results?: unknown[] };

    expect(response.status).toBe(200);
    expect(body.results).toEqual([]);
  });
});
