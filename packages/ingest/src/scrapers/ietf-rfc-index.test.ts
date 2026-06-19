import { describe, expect, it } from "vitest";

import { indexToRawEntries } from "./ietf-rfc-index.js";

describe("ietf rfc index scraper", () => {
  it("maps RFC title acronyms to raw entries", () => {
    const entries = indexToRawEntries(
      [
        "<rfc-index>",
        "<rfc-entry>",
        "<doc-id>RFC1105</doc-id>",
        "<title>Border Gateway Protocol (BGP)</title>",
        "</rfc-entry>",
        "<rfc-entry>",
        "<doc-id>RFC9293</doc-id>",
        "<title>Transmission Control Protocol (TCP)</title>",
        "</rfc-entry>",
        "<rfc-entry>",
        "<doc-id>RFC4022</doc-id>",
        "<title>Management Information Base for the Transmission Control Protocol (TCP)</title>",
        "</rfc-entry>",
        "</rfc-index>"
      ].join("\n"),
      "2026-06-20T00:00:00.000Z"
    );

    expect(entries).toHaveLength(3);
    expect(entries[0]).toMatchObject({
      domains: ["ietf", "rfc", "networking", "standards"],
      examples: ["RFC1105, Title"],
      expansion: "Border Gateway Protocol",
      meaning: "Border Gateway Protocol",
      term: "BGP"
    });
    expect(entries[0]?.sources[0]).toMatchObject({
      license: "LicenseRef-IETF-TLP-5.0",
      publisher: "RFC Editor",
      snippet: "RFC1105, Title: Border Gateway Protocol (BGP)",
      source_quality: "canonical",
      title: "RFC1105 Title",
      url: "https://www.rfc-editor.org/info/rfc1105"
    });
    expect(entries[1]).toMatchObject({
      expansion: "Transmission Control Protocol",
      term: "TCP"
    });
    expect(entries[2]).toMatchObject({
      expansion: "Transmission Control Protocol",
      term: "TCP"
    });
  });

  it("skips titles without final acronym expansions or direct definitions", () => {
    const entries = indexToRawEntries(
      [
        "<rfc-index>",
        "<rfc-entry>",
        "<doc-id>RFC5321</doc-id>",
        "<title>Simple Mail Transfer Protocol</title>",
        "</rfc-entry>",
        "<rfc-entry>",
        "<doc-id>RFC49</doc-id>",
        "<title>Conversations with S. Crocker (UCLA)</title>",
        "</rfc-entry>",
        "<rfc-entry>",
        "<doc-id>RFC3293</doc-id>",
        "<title>General Switch Management Protocol (GSMP) Packet Encapsulations for Asynchronous Transfer Mode (ATM), Ethernet and Transmission Control Protocol (TCP)</title>",
        "</rfc-entry>",
        "</rfc-index>"
      ].join("\n"),
      "2026-06-20T00:00:00.000Z"
    );

    expect(entries).toHaveLength(0);
  });
});
