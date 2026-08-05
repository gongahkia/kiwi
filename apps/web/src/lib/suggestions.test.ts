import { describe, expect, it } from "vitest";

import {
  getSuggestedEdits,
  resetSuggestedEditsForTest,
  reviewSuggestedEdit,
  submitEntryEditSuggestion,
  submitNewEntrySuggestion,
  validateSuggestedEntry,
  validateSuggestedEntryEdit
} from "./suggestions";

describe("suggestions", () => {
  it("validates and queues new entry suggestions", async () => {
    resetSuggestedEditsForTest();
    const input = validateSuggestedEntry({
      domains: ["web"],
      expansion: "Document Object Model",
      meaning: "Browser document tree API.",
      source_url: "https://example.com/dom",
      term: "DOM"
    });

    expect(input).not.toBeNull();
    const suggestion = await submitNewEntrySuggestion("team_1", "user_admin", input!);
    expect(suggestion).toMatchObject({ actor_id: "user_admin", status: "pending" });
    expect(await getSuggestedEdits()).toHaveLength(1);
    resetSuggestedEditsForTest();
  });

  it("rejects invalid source URLs", () => {
    expect(
      validateSuggestedEntry({
        domains: ["web"],
        expansion: "Document Object Model",
        meaning: "Browser document tree API.",
        source_url: "not-a-url",
        term: "DOM"
      })
    ).toBeNull();
  });

  it("queues edit suggestions against an existing entry", async () => {
    resetSuggestedEditsForTest();
    const input = validateSuggestedEntryEdit({
      expansion: "Updated expansion",
      meaning: "Updated meaning.",
      source_url: "https://example.com/edit"
    });

    expect(input).not.toBeNull();
    const suggestion = await submitEntryEditSuggestion("team_1", "user_admin", "seed-dom", input!, {
      expansion: "Old expansion"
    });
    expect(suggestion).toMatchObject({
      status: "pending",
      target_id: "seed-dom"
    });
    expect(await getSuggestedEdits()).toHaveLength(1);
    resetSuggestedEditsForTest();
  });

  it("reviews and edits queued suggestions", async () => {
    resetSuggestedEditsForTest();
    const input = validateSuggestedEntry({
      domains: ["web"],
      expansion: "Document Object Model",
      meaning: "Browser document tree API.",
      source_url: "https://example.com/dom",
      term: "DOM"
    });
    const suggestion = await submitNewEntrySuggestion("team_1", "user_admin", input!);
    const reviewed = await reviewSuggestedEdit("team_1", suggestion.id, "reviewer", "approved", {
      ...input!,
      meaning: "Updated meaning."
    });

    expect(reviewed).toMatchObject({
      reviewed_by: "reviewer",
      status: "approved"
    });
    expect(reviewed.after_jsonb).toMatchObject({ meaning: "Updated meaning." });
    resetSuggestedEditsForTest();
  });
});
