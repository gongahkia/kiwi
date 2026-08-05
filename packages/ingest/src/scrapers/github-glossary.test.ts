import { describe, expect, it } from "vitest";

import { parseGithubGlossaryMarkdown } from "./github-glossary.js";

const options = {
  license: "MIT",
  publisher: "Example repo",
  retrievedAt: "2026-07-10T00:00:00.000Z",
  sourceUrl: "https://raw.githubusercontent.com/example/repo/main/GLOSSARY.md"
};

describe("GitHub glossary scraper", () => {
  it("parses GLOSSARY.md tables with domains and alternatives", () => {
    const entries = parseGithubGlossaryMarkdown(
      `
| Term | Expansion | Meaning | Domains | Alternatives |
| --- | --- | --- | --- | --- |
| CAP | Change Approval Process | Release review gate. | deploys, ops | CAB |
`,
      options
    );

    expect(entries).toEqual([
      expect.objectContaining({
        contemporaries: ["CAB"],
        domains: ["deploys", "ops"],
        expansion: "Change Approval Process",
        meaning: "Release review gate.",
        term: "CAP"
      })
    ]);
    expect(entries[0]?.sources[0]).toMatchObject({
      license: "MIT",
      publisher: "Example repo",
      source_quality: "community",
      url: options.sourceUrl
    });
  });

  it("parses heading-style glossary entries", () => {
    const entries = parseGithubGlossaryMarkdown(
      `
## SLO - Service Level Objective
### RTO: Recovery Time Objective
`,
      { ...options, domains: ["ops"] }
    );

    expect(entries.map((entry) => [entry.term, entry.expansion, entry.domains])).toEqual([
      ["SLO", "Service Level Objective", ["ops"]],
      ["RTO", "Recovery Time Objective", ["ops"]]
    ]);
  });
});
