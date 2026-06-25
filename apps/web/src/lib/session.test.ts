import { describe, expect, it } from "vitest";

import { sessionUserFromToken, testSessionToken } from "./session";

describe("session role helpers", () => {
  it("parses test admin sessions", async () => {
    await expect(sessionUserFromToken(testSessionToken())).resolves.toMatchObject({
      id: "user_admin",
      role: "admin",
      teamId: "team_1"
    });
  });

  it("parses member sessions", async () => {
    await expect(
      sessionUserFromToken(testSessionToken({ role: "member", userId: "user_platform" }))
    ).resolves.toMatchObject({
      id: "user_platform",
      role: "member"
    });
  });
});
