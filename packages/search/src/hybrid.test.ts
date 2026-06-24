import { describe, expect, it } from "vitest";

import benchmarkReport from "../fixtures/dev-tooling-acronyms-benchmark.json" with { type: "json" };
import corpus from "../fixtures/dev-tooling-acronyms.json" with { type: "json" };
import { evaluateBenchmarkGate } from "./benchmark-gate.js";
import { searchHybrid, type HybridSearchCandidate } from "./hybrid.js";

const candidates: HybridSearchCandidate[] = corpus.map((entry, index) => ({
  expansions: [entry.expected_answer],
  id: `benchmark-${index}`,
  term: entry.acronym
}));

function runBenchmark(): typeof benchmarkReport {
  let top1Hits = 0;
  let top5Hits = 0;

  corpus.forEach((entry, index) => {
    const matches = searchHybrid(entry.query, candidates, { limit: 5 });
    const expectedId = `benchmark-${index}`;

    if (matches[0]?.candidate.id === expectedId) top1Hits += 1;
    if (matches.some((match) => match.candidate.id === expectedId)) top5Hits += 1;
  });

  return {
    corpus: "dev-tooling-acronyms.json",
    engine: "searchHybrid",
    total_cases: corpus.length,
    top_1_hits: top1Hits,
    top_1_hit_rate: top1Hits / corpus.length,
    top_5_hits: top5Hits,
    top_5_hit_rate: top5Hits / corpus.length
  };
}

describe("searchHybrid", () => {
  it("uses context tokens to disambiguate overloaded acronyms", () => {
    const [top] = searchHybrid("cap theorem", [
      {
        expansions: ["Common Agricultural Policy"],
        id: "cap-policy",
        term: "CAP"
      },
      {
        expansions: ["Consistency Availability Partition tolerance theorem"],
        id: "cap-theorem",
        term: "CAP"
      }
    ]);

    expect(top?.candidate.id).toBe("cap-theorem");
  });

  it("boosts exact multi-word term matches", () => {
    const [top] = searchHybrid("access control", [
      {
        expansions: ["Access"],
        id: "access",
        term: "Access"
      },
      {
        expansions: ["Security authorization model"],
        id: "access-control",
        term: "Access Control"
      }
    ]);

    expect(top?.candidate.id).toBe("access-control");
  });

  it("boosts results whose contemporaries match the query", () => {
    const matches = searchHybrid("kafka alternatives", [
      {
        contemporaries: ["RabbitMQ", "NATS"],
        expansions: ["Distributed event streaming platform"],
        id: "kafka",
        term: "Kafka"
      },
      {
        contemporaries: ["Kafka"],
        expansions: ["Message broker"],
        id: "nats",
        term: "NATS"
      },
      {
        expansions: ["Columnar embedded analytics database"],
        id: "duckdb",
        term: "DuckDB"
      }
    ]);

    expect(matches.map((match) => match.candidate.id)).toEqual(["kafka", "nats"]);
    expect(matches[1]?.score_breakdown.contemporary).toBeGreaterThan(0);
  });

  it("meets the dev-tooling acronym benchmark gate", () => {
    const result = runBenchmark();
    const gate = evaluateBenchmarkGate(result, benchmarkReport);

    expect(gate).toEqual({ failures: [], ok: true });
    expect(result.total_cases).toBe(benchmarkReport.total_cases);
    expect(result.top_1_hit_rate).toBeGreaterThanOrEqual(0.9);
    expect(result.top_5_hit_rate).toBeGreaterThanOrEqual(0.98);
  }, 15_000);
});
