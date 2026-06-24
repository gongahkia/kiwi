import { describe, expect, it } from "vitest";

import { checkWriteRateLimit, resetWriteRateLimitsForTest } from "./write-rate-limit";

describe("write rate limit", () => {
  it("limits writes per action and actor", () => {
    resetWriteRateLimitsForTest();
    const env = { WAT_CUSTOM_ENTRY_WRITE_LIMIT: "1" };
    const now = new Date("2026-06-24T12:00:00.000Z");

    expect(checkWriteRateLimit("custom-entry", "user_1", env, now)).toMatchObject({
      allowed: true,
      limit: 1,
      remaining: 0,
      reset_at: "2026-06-25T00:00:00.000Z"
    });
    expect(checkWriteRateLimit("custom-entry", "user_1", env, now)).toMatchObject({
      allowed: false,
      limit: 1,
      remaining: 0
    });
    expect(checkWriteRateLimit("team-import", "user_1", env, now)).toMatchObject({
      allowed: true
    });
  });
});
