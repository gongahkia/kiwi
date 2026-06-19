import { describe, expect, it } from "vitest";

import { markdownToRawEntry } from "./cncf-glossary.js";

describe("cncf glossary scraper", () => {
  it("maps English acronym titles to raw entries", () => {
    const entry = markdownToRawEntry(
      "content/en/application-programming-interface.md",
      [
        "---",
        "title: Application Programming Interface (API)",
        "status: Completed",
        "category: technology",
        'tags: ["architecture", "fundamental", ""]',
        "---",
        "",
        "An API is a way for computer programs to interact with each other.",
        "",
        "## Problem it addresses",
        "",
        "Longer section."
      ].join("\n"),
      "2026-06-20T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["cncf", "cloud native", "lang:en", "technology", "architecture", "fundamental"],
      expansion: "Application Programming Interface",
      meaning: "An API is a way for computer programs to interact with each other.",
      term: "API"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "CC-BY-4.0",
      publisher: "CNCF Cloud Native Glossary",
      source_quality: "canonical",
      url: "https://github.com/cncf/glossary/blob/main/content/en/application-programming-interface.md"
    });
  });

  it("keeps localized glossary terms sourced by language", () => {
    const entry = markdownToRawEntry(
      "content/es/application-programming-interface.md",
      [
        "---",
        "title: Interfaz de programación de aplicaciones (API)",
        "status: Completed",
        "category: Tecnología",
        'tags: ["arquitectura", "fundamento", ""]',
        "---",
        "",
        "Una API es una manera en la que los programas interactúan entre sí."
      ].join("\n"),
      "2026-06-20T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["cncf", "cloud native", "lang:es", "tecnología", "arquitectura", "fundamento"],
      expansion: "Interfaz de programación de aplicaciones",
      meaning: "Una API es una manera en la que los programas interactúan entre sí.",
      term: "API"
    });
  });
});
