import { describe, expect, it } from "vitest";

import {
  glossaryWikitextToRawEntries,
  linkedConceptsToRawEntries,
  outlineWikitextToRawEntries,
  wikitextToRawEntries
} from "./wikipedia-outline.js";

const retrievedAt = "2026-06-24T00:00:00.000Z";
const pageUrl = "https://en.wikipedia.org/wiki/Glossary_of_computer_science";

describe("wikipedia outline scraper", () => {
  it("maps glossary term and definition templates to secondary entries", () => {
    const entries = glossaryWikitextToRawEntries(
      "Glossary of computer science",
      [
        "{{term|[[abstract data type]] (ADT)}}",
        "{{defn|A [[mathematical model]] for {{gli|data type|data types}}.}}",
        "{{defn|no=2|A second sense that should not duplicate the term.}}",
        "{{term|[[Abstraction (software engineering)|abstraction]]}}",
        "{{defn|no=1|In [[software engineering]], the process of removing details.}}"
      ].join("\n"),
      pageUrl,
      retrievedAt
    );

    expect(entries).toHaveLength(2);
    expect(entries[0]).toMatchObject({
      aliases: ["ADT"],
      expansion: "abstract data type",
      meaning: "A mathematical model for data types.",
      term: "abstract data type"
    });
    expect(entries[0]?.domains).toEqual(expect.arrayContaining(["wikipedia", "glossary"]));
    expect(entries[0]?.sources[0]).toMatchObject({
      license: "CC-BY-SA-4.0",
      publisher: "Wikipedia contributors",
      source_quality: "secondary",
      url: pageUrl
    });
  });

  it("maps outline bullets with section context and descriptions", () => {
    const entries = outlineWikitextToRawEntries(
      "Outline of computer science",
      [
        "== Fields of computer science ==",
        "* [[Artificial intelligence]] - Intelligence exhibited by machines.",
        "** [[Machine learning]] &ndash; Study of algorithms that improve through data.",
        "* [[Formal language]]"
      ].join("\n"),
      "https://en.wikipedia.org/wiki/Outline_of_computer_science",
      retrievedAt
    );

    expect(entries.map((entry) => entry.term)).toEqual([
      "Artificial intelligence",
      "Machine learning",
      "Formal language"
    ]);
    expect(entries[1]).toMatchObject({
      domains: [
        "wikipedia",
        "computer science",
        "computing",
        "outline",
        "outline of computer science",
        "fields of computer science"
      ],
      meaning: "Study of algorithms that improve through data."
    });
    expect(entries[2]?.meaning).toBe(
      "Formal language is listed in Wikipedia's Outline of computer science."
    );
  });

  it("adds linked concepts and dedupes primary page entries first", () => {
    const entries = wikitextToRawEntries(
      "Glossary of computer science",
      "glossary",
      "== A ==\n{{term|[[algorithm]]}}\n{{defn|A finite sequence of instructions using [[logic]].}}",
      pageUrl,
      retrievedAt
    );

    expect(entries.find((entry) => entry.term === "algorithm")?.meaning).toBe(
      "A finite sequence of instructions using logic."
    );
    expect(entries.find((entry) => entry.term === "logic")).toMatchObject({
      expansion: "logic",
      meaning: "logic is a computing concept linked from Wikipedia's Glossary of computer science."
    });
  });

  it("extracts only article links from linked concepts", () => {
    const entries = linkedConceptsToRawEntries(
      "Outline of computing",
      [
        "* [[Computer science]]",
        "* [[File:Example.svg]]",
        "* [[Category:Computing]]",
        "* [[Computer programming|programming]]"
      ].join("\n"),
      "https://en.wikipedia.org/wiki/Outline_of_computing",
      retrievedAt
    );

    expect(entries.map((entry) => entry.term)).toEqual(["Computer science", "programming"]);
  });
});
