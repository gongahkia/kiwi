import { describe, expect, it } from "vitest";

import {
  getSuggestedEdits,
  resetSuggestedEditsForTest,
  submitNewEntrySuggestion,
  validateSuggestedEntry
} from "./suggestions";

describe("suggestions", () => {
  it("validates and queues new entry suggestions", () => {
    resetSuggestedEditsForTest();
    const input = validateSuggestedEntry({
      domains: ["web"],
      expansion: "Document Object Model",
      meaning: "Browser document tree API.",
      source_url: "https://example.com/dom",
      term: "DOM"
    });

    expect(input).not.toBeNull();
    const suggestion = submitNewEntrySuggestion("user_admin", input!);
    expect(suggestion).toMatchObject({ actor_id: "user_admin", status: "pending" });
    expect(getSuggestedEdits()).toHaveLength(1);
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
});
