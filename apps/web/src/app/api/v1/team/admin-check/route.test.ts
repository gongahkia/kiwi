import { afterEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { resetApiKeysForTest, seedApiKeyForTest } from "@/lib/api-keys";
import { GET } from "./route";

function request(user: string, headers: Record<string, string> = {}) {
  return new NextRequest(`https://wat.example.com/api/v1/team/admin-check?user=${user}`, {
    headers: {
      authorization: "Bearer test-key",
      "x-wat-team-id": "team_1",
      ...headers
    }
  });
}

describe("GET /api/v1/team/admin-check", () => {
  afterEach(resetApiKeysForTest);

  it("returns admin status for team admins", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_1" });

    const response = await GET(request("admin@example.com"));
    const body = (await response.json()) as { admin?: boolean };

    expect(response.status).toBe(200);
    expect(body.admin).toBe(true);
  });

  it("returns false for non-admin members", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_1" });

    const response = await GET(request("ops@example.com"));
    const body = (await response.json()) as { admin?: boolean };

    expect(response.status).toBe(200);
    expect(body.admin).toBe(false);
  });

  it("requires api and team scope", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_1" });

    expect((await GET(request("admin@example.com", { authorization: "Bearer bad" }))).status).toBe(
      401
    );
    expect((await GET(request("admin@example.com", { "x-wat-team-id": "team_2" }))).status).toBe(
      403
    );
  });
});
