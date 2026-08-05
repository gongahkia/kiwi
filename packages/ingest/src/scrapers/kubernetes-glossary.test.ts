import { describe, expect, it } from "vitest";

import { markdownToRawEntry } from "./kubernetes-glossary.js";

describe("kubernetes glossary scraper", () => {
  it("maps glossary markdown to canonical raw entries", () => {
    const entry = markdownToRawEntry(
      "cidr.md",
      `---
title: CIDR
id: cidr
short_description: >
  CIDR is a notation for describing blocks of IP addresses.
tags:
- networking
---
CIDR (Classless Inter-Domain Routing) is a notation for describing blocks of IP addresses.

<!--more-->

More content.
`,
      "2026-06-19T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["kubernetes", "networking"],
      expansion: "Classless Inter-Domain Routing",
      meaning: "CIDR is a notation for describing blocks of IP addresses.",
      term: "CIDR"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "CC-BY-4.0",
      publisher: "Kubernetes Documentation",
      source_quality: "canonical",
      url: "https://kubernetes.io/docs/reference/glossary/?all=true#term-cidr"
    });
  });
});
