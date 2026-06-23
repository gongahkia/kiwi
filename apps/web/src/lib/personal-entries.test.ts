import { describe, expect, it } from "vitest";

import {
  createPersonalEntry,
  deletePersonalEntry,
  getPersonalEntries,
  personalEntriesCsv,
  resetPersonalEntriesForTest,
  updatePersonalEntry,
  type PersonalEntry
} from "./personal-entries";

describe("personal entries", () => {
  it("scopes CRUD to the owning user", () => {
    resetPersonalEntriesForTest();
    const entry: PersonalEntry = {
      domains: ["private"],
      expansion: "Customer Access Policy",
      id: "personal-cap",
      meaning: "My private customer access definition.",
      sources: [
        {
          license: "proprietary-personal",
          publisher: "wat dev fixture",
          retrieved_at: "2026-06-19T00:00:00.000Z",
          snippet: "CAP is a private access policy note.",
          title: "personal glossary fixture",
          url: "https://example.com/personal/cap"
        }
      ],
      term: "CAP"
    };

    expect(createPersonalEntry("user_a", entry)).toEqual(entry);
    expect(getPersonalEntries("user_b")).toEqual([]);
    expect(personalEntriesCsv("user_a")).toContain("personal-cap");
    expect(personalEntriesCsv("user_b")).not.toContain("personal-cap");
    expect(
      updatePersonalEntry("user_a", entry.id, { meaning: "Updated private note." })
    ).toMatchObject({ meaning: "Updated private note." });
    expect(deletePersonalEntry("user_a", entry.id)).toMatchObject({ id: entry.id });
    expect(getPersonalEntries("user_a")).toEqual([]);
    resetPersonalEntriesForTest();
  });
});
