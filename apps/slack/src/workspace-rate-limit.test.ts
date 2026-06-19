import { describe, expect, it } from "vitest";

import {
  checkWorkspaceRateLimit,
  workspaceRateLimitConfigFromEnv
} from "./workspace-rate-limit.js";

describe("workspace rate limit", () => {
  it("uses a 30 per minute default", () => {
    expect(workspaceRateLimitConfigFromEnv({})).toEqual({
      limit: 30,
      windowMs: 60_000
    });
  });

  it("allows 30 workspace calls then throttles gracefully", () => {
    const store = new Map();
    const config = { limit: 30, windowMs: 60_000 };
    let decision = checkWorkspaceRateLimit("T123", config, store, 0);

    for (let index = 1; index < 30; index += 1) {
      decision = checkWorkspaceRateLimit("T123", config, store, index);
    }

    expect(decision).toMatchObject({
      allowed: true,
      remaining: 0,
      workspaceId: "T123"
    });
    expect(checkWorkspaceRateLimit("T123", config, store, 30)).toMatchObject({
      allowed: false,
      limit: 30,
      remaining: 0,
      retryAfter: 60,
      workspaceId: "T123"
    });
  });

  it("resets after the window elapses", () => {
    const store = new Map();
    const config = { limit: 1, windowMs: 1000 };

    expect(checkWorkspaceRateLimit("T123", config, store, 0).allowed).toBe(true);
    expect(checkWorkspaceRateLimit("T123", config, store, 1).allowed).toBe(false);
    expect(checkWorkspaceRateLimit("T123", config, store, 1001)).toMatchObject({
      allowed: true,
      remaining: 0
    });
  });

  it("requires a workspace id", () => {
    expect(() => checkWorkspaceRateLimit("")).toThrow("workspaceId is required");
  });
});
