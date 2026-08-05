import { afterEach, describe, expect, it } from "vitest";

import { hasApiScope, resolveApiIdentity } from "./api-identity";
import { resetApiKeysForTest, seedApiKeyForTest } from "./api-keys";

describe("api identity", () => {
  afterEach(() => resetApiKeysForTest());

  it("allows anonymous requests without a token", async () => {
    const result = await resolveApiIdentity(new Headers());

    expect(result).toEqual({ identity: { type: "anonymous" }, ok: true });
  });

  it("accepts bearer tokens and attaches user/team scope", async () => {
    seedApiKeyForTest({ key: "secret", teamId: "team_1" });
    const headers = new Headers({
      authorization: "Bearer secret",
      "x-wat-team-id": "team_1",
      "x-wat-user-id": "user_1"
    });
    const result = await resolveApiIdentity(headers);

    expect(result).toEqual({
      identity: {
        createdBy: "user_admin",
        scopes: ["admin", "search", "suggest", "write"],
        teamId: "team_1",
        tokenId: expect.stringContaining("test-api-key"),
        type: "api",
        userId: "user_1"
      },
      ok: true
    });
  });

  it("derives team scope from the DB key", async () => {
    seedApiKeyForTest({ key: "secret", teamId: "team_default" });
    const result = await resolveApiIdentity(new Headers({ authorization: "Bearer secret" }));

    expect(result).toEqual({
      identity: {
        createdBy: "user_admin",
        scopes: ["admin", "search", "suggest", "write"],
        teamId: "team_default",
        tokenId: expect.stringContaining("test-api-key"),
        type: "api",
        userId: undefined
      },
      ok: true
    });
  });

  it("rejects invalid api keys", async () => {
    seedApiKeyForTest({ key: "secret", teamId: "team_1" });
    const result = await resolveApiIdentity(new Headers({ "x-api-key": "wrong" }));

    expect(result).toEqual({ error: "invalid_api_key", ok: false, status: 401 });
  });

  it("rejects mismatched requested team scope", async () => {
    seedApiKeyForTest({ key: "secret", teamId: "team_1" });
    const result = await resolveApiIdentity(
      new Headers({ authorization: "Bearer secret", "x-wat-team-id": "team_2" })
    );

    expect(result).toEqual({ error: "team_scope_mismatch", ok: false, status: 403 });
  });

  it("checks explicit and admin-implied scopes", () => {
    expect(hasApiScope({ scopes: ["search"], teamId: "team_1", type: "api" }, "search")).toBe(true);
    expect(hasApiScope({ scopes: ["search"], teamId: "team_1", type: "api" }, "write")).toBe(false);
    expect(hasApiScope({ scopes: ["admin"], teamId: "team_1", type: "api" }, "write")).toBe(true);
    expect(hasApiScope({ type: "anonymous" }, "search")).toBe(false);
  });
});
