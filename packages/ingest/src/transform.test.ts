import { describe, expect, it } from "vitest";

import { transformRawEntry } from "./transform.js";

describe("transformRawEntry", () => {
  it("normalizes term and expansion into a dedup key", () => {
    const entry = transformRawEntry({
      expansion: "Consistency, Availability, Partition tolerance",
      sources: [
        {
          license: "CC-BY-SA-4.0",
          publisher: "Example",
          retrieved_at: "2026-01-01T00:00:00.000Z",
          url: "https://example.com/cap"
        }
      ],
      term: "C.A.P."
    });

    expect(entry.term_normalized).toBe("c a p");
    expect(entry.expansion_normalized).toBe("consistency availability partition tolerance");
    expect(entry.dedup_key).toBe("c a p:consistency availability partition tolerance");
  });

  it("extracts canonical citations from raw sources", () => {
    const entry = transformRawEntry({
      expansion: "Representational State Transfer",
      meaning: "An architectural style for distributed hypermedia systems.",
      sources: [
        {
          license: "MIT",
          publisher: "Fielding dissertation",
          retrieved_at: "2026-01-01T00:00:00.000Z",
          snippet: "REST is defined in the dissertation.",
          source_quality: "canonical",
          title: "Architectural Styles",
          url: "https://example.com/rest"
        }
      ],
      term: "REST"
    });

    expect(entry.sources).toEqual([
      {
        license: "MIT",
        publisher: "Fielding dissertation",
        retrieved_at: "2026-01-01T00:00:00.000Z",
        snippet: "REST is defined in the dissertation.",
        source_quality: "canonical",
        title: "Architectural Styles",
        url: "https://example.com/rest"
      }
    ]);
  });

  it("normalizes optional contemporaries", () => {
    const entry = transformRawEntry({
      contemporaries: [" Kafka ", "", "kafka", "NATS"],
      expansion: "Cloud Events",
      sources: [
        {
          license: "MIT",
          publisher: "Example",
          retrieved_at: "2026-01-01T00:00:00.000Z",
          url: "https://example.com/cloud-events"
        }
      ],
      term: "CloudEvents"
    });

    expect(entry.contemporaries).toEqual(["Kafka", "NATS"]);
  });

  it("normalizes optional aliases", () => {
    const entry = transformRawEntry({
      aliases: [" Cloud Native Technology ", "", "cloud native technology", "Cloud Native Stack"],
      expansion: "Cloud Native Technology",
      sources: [
        {
          license: "CC-BY-4.0",
          publisher: "Example",
          retrieved_at: "2026-01-01T00:00:00.000Z",
          url: "https://example.com/cloud-native"
        }
      ],
      term: "Cloud Native"
    });

    expect(entry.aliases).toEqual(["Cloud Native Technology", "Cloud Native Stack"]);
  });

  it("defaults missing contemporaries to an empty array", () => {
    const entry = transformRawEntry({
      expansion: "Representational State Transfer",
      sources: [
        {
          license: "MIT",
          publisher: "Example",
          retrieved_at: "2026-01-01T00:00:00.000Z",
          url: "https://example.com/rest"
        }
      ],
      term: "REST"
    });

    expect(entry.contemporaries).toEqual([]);
  });

  it("defaults missing aliases to an empty array", () => {
    const entry = transformRawEntry({
      expansion: "Representational State Transfer",
      sources: [
        {
          license: "MIT",
          publisher: "Example",
          retrieved_at: "2026-01-01T00:00:00.000Z",
          url: "https://example.com/rest"
        }
      ],
      term: "REST"
    });

    expect(entry.aliases).toEqual([]);
  });
});
