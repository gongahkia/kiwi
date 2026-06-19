import { describe, expect, it } from "vitest";

import { htmlToRawEntries } from "./postgresql-glossary.js";

describe("postgresql glossary scraper", () => {
  it("maps glossary HTML terms to canonical raw entries", () => {
    const [entry] = htmlToRawEntries(
      `<dl>
        <dt id="GLOSSARY-ACID"><span class="glossterm">ACID</span></dt>
        <dd class="glossdef">
          <p><a href="#atomicity">Atomicity</a>, Consistency, Isolation, and Durability. This set of properties matters.</p>
        </dd>
      </dl>`,
      "2026-06-19T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["postgresql", "database"],
      expansion: "Atomicity, Consistency, Isolation, and Durability",
      meaning: "Atomicity, Consistency, Isolation, and Durability. This set of properties matters.",
      term: "ACID"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "PostgreSQL",
      publisher: "PostgreSQL Documentation",
      source_quality: "canonical",
      url: "https://www.postgresql.org/docs/current/glossary.html#GLOSSARY-ACID"
    });
  });
});
