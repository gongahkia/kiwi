import { describe, expect, it } from "vitest";

import { assignConfidenceTier } from "../confidence.js";
import { transformRawEntry } from "../transform.js";
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
    expect(entry?.sources[1]).toMatchObject({
      license: "CC-BY-4.0",
      publisher: "CNCF Cloud Native Glossary",
      source_quality: "canonical",
      url: "https://glossary.cncf.io/application-programming-interface/"
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
    expect(entry?.sources[1]?.url).toBe(
      "https://glossary.cncf.io/es/application-programming-interface/"
    );
  });

  it("captures Cloud Native as a T1 cloud native concept", () => {
    const entry = markdownToRawEntry(
      "content/en/cloud-native-tech.md",
      [
        "---",
        "title: Cloud Native Technology",
        "status: Completed",
        "category: Concept",
        'tags: ["fundamental", "", ""]',
        "---",
        "",
        "Cloud native technologies, also referred to as the cloud native stack, build scalable applications.",
        "",
        "## Problem it addresses",
        "",
        "Longer section."
      ].join("\n"),
      "2026-06-20T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      aliases: ["Cloud Native Technology", "Cloud Native Stack"],
      domains: ["cncf", "cloud native", "lang:en", "concept", "fundamental"],
      expansion: "Cloud Native Technology",
      meaning:
        "Cloud native technologies, also referred to as the cloud native stack, build scalable applications.",
      term: "Cloud Native"
    });
    if (!entry) throw new Error("expected Cloud Native entry");
    expect(assignConfidenceTier(transformRawEntry(entry)).confidence_tier).toBe("T1");
  });

  it("captures Service Mesh as a T1 cloud native concept", () => {
    const entry = markdownToRawEntry(
      "content/en/service-mesh.md",
      [
        "---",
        "title: Service Mesh",
        "status: Completed",
        "category: technology",
        'tags: ["networking", "", ""]',
        "---",
        "",
        "Service meshes manage traffic between services.",
        "",
        "## Problem it addresses",
        "",
        "Longer section."
      ].join("\n"),
      "2026-06-20T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["cncf", "cloud native", "lang:en", "technology", "networking"],
      expansion: "Service Mesh",
      term: "Service Mesh"
    });
    if (!entry) throw new Error("expected Service Mesh entry");
    expect(assignConfidenceTier(transformRawEntry(entry)).confidence_tier).toBe("T1");
  });
});
