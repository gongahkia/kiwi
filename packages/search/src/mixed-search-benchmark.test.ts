import { describe, expect, it } from "vitest";

import benchmarkReport from "../fixtures/mixed-search-benchmark-report.json" with { type: "json" };
import { evaluateBenchmarkGate } from "./benchmark-gate.js";
import { buildMixedBenchmark, runMixedBenchmark } from "./mixed-search-benchmark.js";

const rows = buildMixedBenchmark();

describe("mixed search benchmark", () => {
  it("covers 500 acronyms, 300 concepts, and 200 systems", () => {
    const counts = rows.reduce(
      (current, row) => ({
        ...current,
        [row.kind]: current[row.kind] + 1
      }),
      { acronym: 0, concept: 0, system: 0 }
    );

    expect(rows).toHaveLength(1000);
    expect(counts.acronym).toBe(500);
    expect(counts.concept).toBe(300);
    expect(counts.system).toBe(200);
    expect(new Set(rows.map((row) => row.query.toLowerCase()))).toHaveLength(1000);

    for (const row of rows) {
      expect(row.source_url).toMatch(/^https?:\/\//);
      expect(row.source_license).toMatch(/\S/);
    }
  });

  it("keeps hit rates above the v0.1 gate", () => {
    const result = runMixedBenchmark(rows);
    const gate = evaluateBenchmarkGate(result, benchmarkReport);

    expect(gate).toEqual({ failures: [], ok: true });
    expect(result.total_cases).toBe(1000);
    expect(result.top_1_hit_rate).toBeGreaterThanOrEqual(0.9);
    expect(result.top_5_hit_rate).toBeGreaterThanOrEqual(0.98);
  }, 60_000);
});
