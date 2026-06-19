import { describe, expect, it } from "vitest";

import { checkRateLimit, rateLimitConfigFromEnv } from "./rate-limit";

describe("rate limit", () => {
  it("uses env-configured limits", () => {
    expect(
      rateLimitConfigFromEnv({
        WAT_RATE_LIMIT_IP: "2",
        WAT_RATE_LIMIT_TEAM: "4",
        WAT_RATE_LIMIT_USER: "3",
        WAT_RATE_LIMIT_WINDOW_MS: "1000"
      })
    ).toEqual({
      limits: { ip: 2, team: 4, user: 3 },
      windowMs: 1000
    });
  });

  it("limits anonymous requests by ip", () => {
    const store = new Map();
    const subject = { identity: { type: "anonymous" as const }, ip: "203.0.113.10" };
    const config = { limits: { ip: 1, team: 10, user: 10 }, windowMs: 1000 };

    expect(checkRateLimit(subject, config, store, 0)).toMatchObject({
      allowed: true,
      remaining: 0,
      scope: "ip"
    });
    expect(checkRateLimit(subject, config, store, 1)).toMatchObject({
      allowed: false,
      scope: "ip"
    });
  });

  it("limits api requests by user and team", () => {
    const store = new Map();
    const subject = {
      identity: { teamId: "team_1", type: "api" as const, userId: "user_1" },
      ip: "203.0.113.10"
    };
    const config = { limits: { ip: 10, team: 1, user: 10 }, windowMs: 1000 };

    expect(checkRateLimit(subject, config, store, 0)).toMatchObject({
      allowed: true,
      scope: "team"
    });
    expect(checkRateLimit(subject, config, store, 1)).toMatchObject({
      allowed: false,
      scope: "team"
    });
  });
});
