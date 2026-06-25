import { describe, expect, it } from "vitest";

import { checkSuggestionRateLimit, resetSuggestionRateLimitForTest } from "./suggestion-rate-limit";

describe("suggestion rate limit", () => {
  it("rejects the 11th suggestion per user per day", async () => {
    resetSuggestionRateLimitForTest();
    const now = new Date("2026-06-19T00:00:00.000Z");

    for (let index = 0; index < 10; index += 1) {
      expect((await checkSuggestionRateLimit("user_a", 10, now)).allowed).toBe(true);
    }
    expect(await checkSuggestionRateLimit("user_a", 10, now)).toMatchObject({
      allowed: false,
      remaining: 0
    });
    expect((await checkSuggestionRateLimit("user_b", 10, now)).allowed).toBe(true);
    resetSuggestionRateLimitForTest();
  });
});
