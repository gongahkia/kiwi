import { describe, expect, it } from "vitest";

import { isAdminSession, sessionTeamRole, sessionUserId } from "./session";

describe("session role helpers", () => {
  it("maps dev session to admin", () => {
    expect(sessionUserId("dev")).toBe("user_admin");
    expect(isAdminSession("dev")).toBe(true);
  });

  it("rejects member sessions for admin access", () => {
    expect(sessionTeamRole("user_platform")).toBe("member");
    expect(isAdminSession("user_platform")).toBe(false);
  });
});
