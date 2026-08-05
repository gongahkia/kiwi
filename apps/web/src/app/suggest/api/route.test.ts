import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { resetSuggestionRateLimitForTest } from "@/lib/suggestion-rate-limit";
import { testSessionToken } from "@/lib/session";
import { getSuggestedEdits, resetSuggestedEditsForTest } from "@/lib/suggestions";
import { POST } from "./route";

const suggestion = {
  domains: ["ops"],
  expansion: "Recovery Time Objective",
  meaning: "Maximum acceptable restore time.",
  source_url: "https://example.com/rto",
  term: "RTO"
};

function request(body: unknown) {
  return new NextRequest("https://wat.example.com/suggest/api", {
    body: JSON.stringify(body),
    headers: {
      "content-type": "application/json",
      cookie: `next-auth.session-token=${testSessionToken({
        teamId: "team_1",
        userId: "user_1"
      })}`
    },
    method: "POST"
  });
}

describe("POST /suggest/api", () => {
  beforeEach(() => {
    resetSuggestedEditsForTest();
    resetSuggestionRateLimitForTest();
  });

  afterEach(() => {
    resetSuggestedEditsForTest();
    resetSuggestionRateLimitForTest();
  });

  it("ties no-result suggestions to the signed-in user's team", async () => {
    const response = await POST(request(suggestion));
    const body = (await response.json()) as {
      suggestion: { after_jsonb?: { actor_id?: string; team_id?: string }; team_id?: string };
    };

    expect(response.status).toBe(200);
    expect(body.suggestion.team_id).toBe("team_1");
    expect(body.suggestion.after_jsonb).toMatchObject({
      actor_id: "user_1",
      team_id: "team_1"
    });
    await expect(getSuggestedEdits("team_2")).resolves.toHaveLength(0);
  });
});
