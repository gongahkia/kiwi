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
  it("scopes CRUD to the owning user", async () => {
    resetPersonalEntriesForTest();
    const entry: PersonalEntry = {
      contemporaries: ["SAML", "OIDC"],
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

    expect(await createPersonalEntry("user_a", entry)).toEqual(entry);
    expect(await getPersonalEntries("user_b")).toEqual([]);
    expect((await getPersonalEntries("user_a"))[0]?.contemporaries).toEqual(["SAML", "OIDC"]);
    expect(personalEntriesCsv(await getPersonalEntries("user_a"))).toContain("personal-cap");
    expect(personalEntriesCsv(await getPersonalEntries("user_b"))).not.toContain("personal-cap");
    expect(
      await updatePersonalEntry("user_a", entry.id, {
        contemporaries: ["Okta"],
        meaning: "Updated private note."
      })
    ).toMatchObject({ contemporaries: ["Okta"], meaning: "Updated private note." });
    expect(await deletePersonalEntry("user_a", entry.id)).toMatchObject({ id: entry.id });
    expect(await getPersonalEntries("user_a")).toEqual([]);
    resetPersonalEntriesForTest();
  });
});
