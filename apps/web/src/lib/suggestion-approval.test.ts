import { describe, expect, it } from "vitest";

import { getAuditLog, resetAuditLogForTest } from "./audit-log";
import { approveSuggestion } from "./suggestion-approval";
import {
  resetSuggestedEditsForTest,
  submitNewEntrySuggestion,
  validateSuggestedEntry
} from "./suggestions";
import { getTeamEntries, resetTeamEntriesForTest } from "./team-entries";

describe("suggestion approval", () => {
  it("creates a team entry and audit log from an approved suggestion", async () => {
    resetAuditLogForTest();
    resetSuggestedEditsForTest();
    resetTeamEntriesForTest();

    const input = validateSuggestedEntry({
      domains: ["platform"],
      expansion: "Review Queue Check",
      meaning: "Approval flow verification entry.",
      source_url: "https://example.com/rqc",
      term: "RQC"
    });
    const suggestion = await submitNewEntrySuggestion("team_1", "user_platform", input!);
    const result = await approveSuggestion("team_1", suggestion, "user_admin");

    expect((await getTeamEntries()).map((entry) => entry.id)).toContain(result.entry.id);
    expect(await getAuditLog()).toContainEqual(
      expect.objectContaining({
        action: "suggestion.approve.create",
        actor_id: "user_admin",
        after_jsonb: expect.objectContaining({ id: result.entry.id }),
        before_jsonb: null
      })
    );
    resetAuditLogForTest();
    resetSuggestedEditsForTest();
    resetTeamEntriesForTest();
  });
});
