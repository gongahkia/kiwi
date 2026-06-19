import { describe, expect, it } from "vitest";

import { wikitextToRawEntries } from "./wikipedia-acronyms.js";

describe("wikipedia acronyms scraper", () => {
  it("maps acronym list wikitext to raw entries", () => {
    const entries = wikitextToRawEntries(
      "List of acronyms: A",
      [
        "* [[A2ATD]] or A<sup>2</sup>ATD \u2013 (i) Anti-Armour Advanced Technology Demonstration",
        "* [[AAA (disambiguation)|AAA]]",
        "** (i) administration, authorization, and authentication",
        '** [[American Automobile Association]] ("Triple-A")'
      ].join("\n"),
      "https://en.wikipedia.org/wiki/List_of_acronyms:_A",
      "2026-06-19T00:00:00.000Z"
    );

    expect(entries).toHaveLength(3);
    expect(entries[0]).toMatchObject({
      expansion: "Anti-Armour Advanced Technology Demonstration",
      meaning: "Anti-Armour Advanced Technology Demonstration",
      term: "A2ATD"
    });
    expect(entries[1]).toMatchObject({
      expansion: "administration, authorization, and authentication",
      term: "AAA"
    });
    expect(entries[2]?.sources[0]).toMatchObject({
      license: "CC-BY-SA-4.0",
      publisher: "Wikipedia contributors",
      source_quality: "community",
      url: "https://en.wikipedia.org/wiki/List_of_acronyms:_A"
    });
  });
});
