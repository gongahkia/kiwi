import { describe, expect, it } from "vitest";

import { resolveApiIdentity } from "./api-identity";

describe("api identity", () => {
  it("allows anonymous requests without a token", () => {
    const result = resolveApiIdentity(new Headers(), { WAT_API_KEY: "secret" });

    expect(result).toEqual({ identity: { type: "anonymous" }, ok: true });
  });

  it("accepts bearer tokens and attaches user/team scope", () => {
    const headers = new Headers({
      authorization: "Bearer secret",
      "x-wat-team-id": "team_1",
      "x-wat-user-id": "user_1"
    });
    const result = resolveApiIdentity(headers, { WAT_API_KEY: "secret" });

    expect(result).toEqual({
      identity: {
        teamId: "team_1",
        tokenId: "wat_api_key",
        type: "api",
        userId: "user_1"
      },
      ok: true
    });
  });

  it("rejects invalid api keys", () => {
    const result = resolveApiIdentity(new Headers({ "x-api-key": "wrong" }), {
      WAT_API_KEY: "secret"
    });

    expect(result).toEqual({ error: "invalid_api_key", ok: false, status: 401 });
  });
});
