import { describe, expect, it } from "vitest";
import type { SearchEntry } from "@wat/search";

import { scoreEntry, searchEntries } from "./search-core";

function entry(patch: Partial<SearchEntry> = {}): SearchEntry {
  return {
    aliases: [],
    confidence_tier: "T2",
    contemporaries: [],
    domains: ["messaging"],
    expansions: ["Message broker"],
    id: "nats",
    layer: "public",
    meaning_short: "A messaging system.",
    sources: [],
    term: "NATS",
    term_normalized: "nats",
    ...patch
  };
}

describe("scoreEntry", () => {
  it("matches and scores contemporaries", () => {
    const result = scoreEntry("kafka", entry({ contemporaries: ["Kafka"] }));

    expect(result?.entry.id).toBe("nats");
    expect(result?.score_breakdown.contemporary).toBeGreaterThan(0);
  });

  it("surfaces a term and its peers for alternatives queries", () => {
    const matches = searchEntries({
      entries: [
        entry({
          contemporaries: ["RabbitMQ", "NATS"],
          expansions: ["Distributed event streaming platform"],
          id: "kafka",
          term: "Kafka",
          term_normalized: "kafka"
        }),
        entry({ contemporaries: ["Kafka"] }),
        entry({
          domains: ["analytics"],
          expansions: ["Columnar embedded analytics database"],
          id: "duckdb",
          term: "DuckDB",
          term_normalized: "duckdb"
        })
      ],
      query: "kafka alternatives"
    });

    expect(matches.map((match) => match.entry.id)).toEqual(["kafka", "nats"]);
  });
});
