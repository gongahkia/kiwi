import { describe, expect, it } from "vitest";

import { validateTeamEntryDraft } from "./team-entry-form-validation";
import { initialTeamEntries, type TeamEntry } from "./team-entries";

const validEntry: TeamEntry = {
  domains: ["ops"],
  expansion: "Recovery Time Objective",
  id: "team-rto",
  meaning: "Maximum acceptable restore time.",
  sources: [
    {
      license: "proprietary-team",
      publisher: "wat test",
      retrieved_at: "2026-06-24T00:00:00.000Z",
      snippet: "RTO fixture.",
      title: "RTO fixture",
      url: "https://example.com/rto"
    }
  ],
  term: "RTO"
};

describe("team entry form validation", () => {
  it("reports missing fields and invalid source URLs", () => {
    expect(
      validateTeamEntryDraft(
        {
          ...validEntry,
          domains: [],
          expansion: "",
          id: "",
          meaning: "",
          sources: [{ ...validEntry.sources[0]!, url: "not a url" }],
          term: ""
        },
        []
      )
    ).toEqual([
      "id is required",
      "term is required",
      "expansion is required",
      "meaning is required",
      "at least one domain is required",
      "source 0: source url must be valid"
    ]);
  });

  it("reports duplicate ids and duplicate term/expansion pairs", () => {
    expect(
      validateTeamEntryDraft(
        {
          ...validEntry,
          expansion: "Change Approval Process",
          id: "team-example-cap",
          term: "CAP"
        },
        initialTeamEntries
      )
    ).toEqual(["duplicate id", "duplicate term and expansion"]);
  });

  it("allows the edited entry to keep its own id and term pair", () => {
    expect(
      validateTeamEntryDraft(initialTeamEntries[0]!, initialTeamEntries, "team-example-cap")
    ).toEqual([]);
  });
});
