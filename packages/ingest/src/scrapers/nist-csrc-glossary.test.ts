import { describe, expect, it } from "vitest";

import { jsonToRawEntries } from "./nist-csrc-glossary.js";

describe("nist csrc glossary scraper", () => {
  it("maps glossary export JSON to raw entries", () => {
    const entries = jsonToRawEntries(
      {
        parentTerms: [
          {
            term: "Access Control",
            link: "https://csrc.nist.gov/glossary/term/access_control",
            definitions: [
              {
                text: "The process of granting or denying specific requests.",
                sources: [{ text: "NIST SP 800-53 Rev. 5" }]
              }
            ]
          },
          {
            term: "+",
            link: "https://csrc.nist.gov/glossary/term/plus",
            definitions: [{ text: "Addition." }]
          }
        ]
      },
      "2026-06-19T00:00:00.000Z"
    );

    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      domains: ["nist", "security", "privacy"],
      expansion: "Access Control",
      meaning: "The process of granting or denying specific requests.",
      term: "Access Control"
    });
    expect(entries[0]?.sources[0]).toMatchObject({
      license: "NIST-PD",
      publisher: "NIST CSRC Glossary",
      source_quality: "canonical",
      title: "NIST CSRC glossary: Access Control (NIST SP 800-53 Rev. 5)",
      url: "https://csrc.nist.gov/glossary/term/access_control"
    });
  });
});
