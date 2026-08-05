import { describe, expect, it } from "vitest";

import { recordsToRawEntries } from "./d-edge-foss-acronyms.js";

describe("d-edge/foss-acronyms scraper", () => {
  it("maps upstream records to sourced raw entries", () => {
    const [entry] = recordsToRawEntries(
      "acronyms",
      [
        {
          Abbreviation: "CLI",
          Definition: "Command Line Interface",
          Example: '<a href="https://example.com">Example</a>',
          Usage: "I prefer using the CLI because it is faster."
        }
      ],
      "2026-06-19T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["foss"],
      examples: ["Example"],
      expansion: "Command Line Interface",
      meaning: "I prefer using the CLI because it is faster.",
      term: "CLI"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "CC0-1.0",
      publisher: "d-edge/foss-acronyms",
      source_quality: "community",
      url: "https://raw.githubusercontent.com/d-edge/foss-acronyms/main/data/acronyms.json"
    });
  });
});
