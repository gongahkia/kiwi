import { afterEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { resetApiKeysForTest, seedApiKeyForTest } from "@/lib/api-keys";
import { resetSuggestionRateLimitForTest } from "@/lib/suggestion-rate-limit";

import { postApiSuggestion } from "./handler";

function request(body: unknown, headers: Record<string, string> = {}) {
  return new NextRequest("https://wat.example.com/api/v1/suggestions", {
    body: JSON.stringify(body),
    headers: {
      authorization: "Bearer test-key",
      "content-type": "application/json",
      "x-wat-team-id": "team_123",
      "x-wat-user-id": "slack:U123",
      ...headers
    },
    method: "POST"
  });
}

const validSuggestion = {
  domains: ["example", "docs"],
  expansion: "Service Level Objective",
  meaning: "Reliability target for a service.",
  source_url: "https://slack.com/app_redirect?channel=C123",
  term: "SLO"
};

describe("POST /api/v1/suggestions", () => {
  afterEach(() => {
    resetSuggestionRateLimitForTest();
    resetApiKeysForTest();
  });

  it("stores scoped API suggestions", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });
    const response = await postApiSuggestion(request(validSuggestion), {
      createSuggestion: async ({ actorId, suggestion, teamId }) => ({
        actor_id: null,
        after_jsonb: { ...suggestion, actor_id: actorId, team_id: teamId },
        before_jsonb: null,
        created_at: "2026-06-25T00:00:00.000Z",
        id: "suggestion_123",
        status: "pending",
        target_id: null,
        target_type: "entry",
        team_id: teamId
      })
    });

    const body = (await response.json()) as {
      suggestion?: { after_jsonb?: { actor_id?: string }; team_id?: string };
    };
    expect(response.status).toBe(201);
    expect(body.suggestion?.team_id).toBe("team_123");
    expect(body.suggestion?.after_jsonb?.actor_id).toBe("slack:U123");
  });

  it("requires api and team scope", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    expect(
      (await postApiSuggestion(request(validSuggestion, { authorization: "Bearer bad" }))).status
    ).toBe(401);
    expect(
      (await postApiSuggestion(request(validSuggestion, { "x-wat-team-id": "team_999" }))).status
    ).toBe(403);
  });

  it("rejects invalid suggestions", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    const response = await postApiSuggestion(request({ ...validSuggestion, source_url: "bad" }));

    expect(response.status).toBe(400);
  });
});
