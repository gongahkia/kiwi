import { describe, expect, it } from "vitest";

import { teamAdminChecklist } from "./team-admin-checklist";

describe("teamAdminChecklist", () => {
  it("marks import and member steps complete from team state", () => {
    expect(
      teamAdminChecklist({ memberCount: 3, teamEntryCount: 2 }).map((item) => item.complete)
    ).toEqual([true, true, false, false]);
  });

  it("keeps new-team setup steps pending", () => {
    expect(teamAdminChecklist({ memberCount: 1, teamEntryCount: 0 })).toMatchObject([
      { complete: false, href: "/team/admin/import", label: "Import acronyms" },
      { complete: false, href: "/team/admin/members", label: "Invite members" },
      { complete: false, href: "/install/extension", label: "Install extension" },
      { complete: false, href: "/install/slack", label: "Connect Slack" }
    ]);
  });
});
