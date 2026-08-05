import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  checkSlackRateLimit,
  checkWorkspaceRateLimit,
  JsonFileRateLimitStore,
  MemoryRateLimitStore,
  workspaceRateLimitConfigFromEnv
} from "./workspace-rate-limit.js";

describe("workspace rate limit", () => {
  it("uses a 30 per minute default", () => {
    expect(workspaceRateLimitConfigFromEnv({})).toEqual({
      channelLimit: 30,
      limit: 30,
      userLimit: 30,
      workspaceLimit: 30,
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

  it("throttles channel and user scopes", async () => {
    const store = new MemoryRateLimitStore();
    const config = {
      channelLimit: 1,
      limit: 99,
      userLimit: 99,
      windowMs: 60_000,
      workspaceLimit: 99
    };

    await expect(
      checkSlackRateLimit({ channelId: "C1", userId: "U1", workspaceId: "T123" }, config, store, 0)
    ).resolves.toMatchObject({ allowed: true, scope: "workspace" });
    await expect(
      checkSlackRateLimit({ channelId: "C1", userId: "U2", workspaceId: "T123" }, config, store, 1)
    ).resolves.toMatchObject({ allowed: false, scope: "channel" });

    const userStore = new MemoryRateLimitStore();
    await expect(
      checkSlackRateLimit(
        { channelId: "C1", userId: "U1", workspaceId: "T123" },
        { ...config, channelLimit: 99, userLimit: 1 },
        userStore,
        0
      )
    ).resolves.toMatchObject({ allowed: true });
    await expect(
      checkSlackRateLimit(
        { channelId: "C2", userId: "U1", workspaceId: "T123" },
        { ...config, channelLimit: 99, userLimit: 1 },
        userStore,
        1
      )
    ).resolves.toMatchObject({ allowed: false, scope: "user" });
  });

  it("persists counters in a JSON file store", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "wat-slack-rate-limit-"));
    try {
      const filePath = path.join(dir, "limits.json");
      const config = { limit: 1, windowMs: 60_000 };

      await expect(
        checkSlackRateLimit(
          { channelId: "C1", userId: "U1", workspaceId: "T123" },
          config,
          new JsonFileRateLimitStore(filePath),
          0
        )
      ).resolves.toMatchObject({ allowed: true });
      await expect(
        checkSlackRateLimit(
          { channelId: "C2", userId: "U2", workspaceId: "T123" },
          config,
          new JsonFileRateLimitStore(filePath),
          1
        )
      ).resolves.toMatchObject({ allowed: false, scope: "workspace" });
    } finally {
      await rm(dir, { force: true, recursive: true });
    }
  });
});
