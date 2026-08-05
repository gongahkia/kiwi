import { describe, expect, it } from "vitest";
import type { SearchEntry } from "@wat/search";

import { resolveContemporaryTerms } from "./contemporaries";

function entry(patch: Partial<SearchEntry>): SearchEntry {
  return {
    aliases: [],
    confidence_tier: "T2",
    contemporaries: [],
    domains: [],
    expansions: [],
    id: "entry",
    layer: "public",
    meaning_short: "short meaning",
    sources: [],
    term: "Entry",
    term_normalized: "entry",
    ...patch
  };
}

describe("resolveContemporaryTerms", () => {
  it("returns resolved entries and unresolved stubs", () => {
    expect(
      resolveContemporaryTerms(
        ["Kafka", "MissingMQ"],
        [
          entry({
            aliases: ["Apache Kafka"],
            id: "kafka",
            meaning_short: "Distributed event streaming platform.",
            term: "Kafka",
            term_normalized: "kafka"
          })
        ]
      )
    ).toEqual([
      {
        id: "kafka",
        meaning_short: "Distributed event streaming platform.",
        term: "Kafka"
      },
      {
        id: null,
        meaning_short: null,
        term: "MissingMQ"
      }
    ]);
  });

  it("resolves aliases", () => {
    expect(
      resolveContemporaryTerms(
        ["Apache Kafka"],
        [
          entry({
            aliases: ["Apache Kafka"],
            id: "kafka",
            term: "Kafka",
            term_normalized: "kafka"
          })
        ]
      )
    ).toEqual([
      {
        id: "kafka",
        meaning_short: "short meaning",
        term: "Apache Kafka"
      }
    ]);
  });
});
