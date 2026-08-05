import { describe, expect, it } from "vitest";

import { htmlToRawEntries, nextPageUrl } from "./w3c-glossary.js";

describe("w3c glossary scraper", () => {
  it("maps glossary HTML to raw entries with W3C keyword URLs", () => {
    const entries = htmlToRawEntries(
      `
      <p>Showing results 1 - 20 of 1725</p>
      <a href="20" rel="next" accesskey="N">next 20 results</a>
      <dl>
        <dt><a href="/2003/glossary/keyword/All/?keywords=ACSS" title="search">ACSS (Audio cascading style sheets)</a></dt>
        <dd>
          <p class="details">From <a href="https://www.w3.org/People/Berners-Lee/Weaving/glossary.html" title="Glossary of &quot;Weaving the Web&quot;">Glossary of "Weaving the Web"</a> (<a href="https://www.w3.org/People/Berners-Lee/Weaving/glossary.html">1999-07-23</a>)</p>
          <div class="definition">
            A language for telling a computer how to read a Web page aloud. This is now part of CSS2.
          </div>
        </dd>
      </dl>
      `,
      "2026-06-19T00:00:00.000Z"
    );

    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      domains: ["w3c", "web standards"],
      expansion: "Audio cascading style sheets",
      meaning:
        "A language for telling a computer how to read a Web page aloud. This is now part of CSS2.",
      term: "ACSS"
    });
    expect(entries[0]?.sources[0]).toMatchObject({
      license: "W3C",
      publisher: "W3C Glossary and Dictionary",
      source_quality: "canonical",
      title: 'W3C glossary: ACSS (Glossary of "Weaving the Web")',
      url: "https://www.w3.org/2003/glossary/keyword/All/?keywords=ACSS"
    });
  });

  it("resolves relative next-page links", () => {
    expect(
      nextPageUrl(
        '<a href="40" rel="next" accesskey="N">next 20 results</a>',
        "https://www.w3.org/2003/glossary/subglossary/All/20"
      )
    ).toBe("https://www.w3.org/2003/glossary/subglossary/All/40");
  });
});
