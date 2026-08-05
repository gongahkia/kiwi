import { describe, expect, it } from "vitest";

import { textToRawEntries } from "./jargon-file.js";

describe("jargon file scraper", () => {
  it("maps lexicon nodes to public-domain raw entries", () => {
    const entries = textToRawEntries(
      `Node:0, Next:1TBS,
Up:= 0 =

0

Numeric zero, as opposed to the letter \`O'.

Node:1TBS, Next:Appendix A, Previous:0, Up:= 0 =

1TBS // n.

The "One True Brace Style"; see indent style.

Node:Appendix A`,
      "2026-06-19T00:00:00.000Z"
    );

    expect(entries).toHaveLength(2);
    expect(entries[1]).toMatchObject({
      domains: ["hacker culture", "programming"],
      expansion: "1TBS",
      meaning: 'The "One True Brace Style"; see indent style.',
      term: "1TBS"
    });
    expect(entries[1]?.sources[0]).toMatchObject({
      license: "LicenseRef-Public-Domain",
      publisher: "Jargon File",
      source_quality: "canonical"
    });
  });
});
