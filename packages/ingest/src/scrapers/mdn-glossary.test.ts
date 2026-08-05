import { describe, expect, it } from "vitest";

import { markdownToRawEntry } from "./mdn-glossary.js";

describe("mdn glossary scraper", () => {
  it("maps glossary markdown to canonical raw entries", () => {
    const entry = markdownToRawEntry(
      "http/index.md",
      `---
title: HTTP
slug: Glossary/HTTP
---

**HTTP** (HyperText Transfer Protocol) is the underlying network protocol that enables transfer of hypermedia documents on the web.
It is used by {{Glossary("Browser", "browsers")}}.

## See also
`,
      "2026-06-19T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["web platform", "mdn"],
      expansion: "HyperText Transfer Protocol",
      meaning:
        "HTTP (HyperText Transfer Protocol) is the underlying network protocol that enables transfer of hypermedia documents on the web. It is used by browsers.",
      term: "HTTP"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "CC-BY-SA-2.5",
      publisher: "Mozilla Contributors",
      source_quality: "canonical",
      url: "https://developer.mozilla.org/en-US/docs/Glossary/HTTP"
    });
  });
});
