import { describe, expect, it } from "vitest";

import { tsvToRawEntries } from "./linux-foundation-glossary.js";

describe("linux foundation glossary scraper", () => {
  it("maps LF Edge TSV rows to raw entries", () => {
    const entries = tsvToRawEntries(
      [
        "Term\tDefinition\tSee also\tSee also 2\tSee also 3",
        "Edge Computing\tThe delivery of computing capabilities to the logical extremes of a network.\tInfrastructure Edge\tDevice Edge\tLast Mile"
      ].join("\n"),
      "2026-06-19T00:00:00.000Z"
    );

    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      domains: ["linux foundation", "lf edge", "edge computing"],
      examples: ["See also: Infrastructure Edge, Device Edge, Last Mile"],
      expansion: "Edge Computing",
      meaning: "The delivery of computing capabilities to the logical extremes of a network.",
      term: "Edge Computing"
    });
    expect(entries[0]?.sources[0]).toMatchObject({
      license: "CC-BY-SA-4.0",
      publisher: "LF Edge Open Glossary of Edge Computing",
      source_quality: "canonical",
      url: "https://github.com/State-of-the-Edge/glossary/blob/master/edge-glossary.tsv"
    });
  });
});
