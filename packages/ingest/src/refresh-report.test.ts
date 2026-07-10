import { describe, expect, it } from "vitest";

import {
  benchmarkMetrics,
  buildRefreshReport,
  parserErrorSummaries,
  renderRefreshReport
} from "./refresh-report.js";
import type { DeltaSummary } from "./delta-summary.js";

function summary(
  source: string,
  counts: { added?: number; changed?: number; removed?: number }
): DeltaSummary {
  const entry = {
    aliases: [],
    dedup_key: "api:application programming interface",
    contemporaries: [],
    domains: ["web"],
    examples: [],
    expansion_normalized: "application programming interface",
    expansions: ["Application Programming Interface"],
    meaning_short: "Interface for software systems.",
    sources: [],
    term: "API",
    term_normalized: "api"
  };
  return {
    added: Array.from({ length: counts.added ?? 0 }, () => entry),
    changed: Array.from({ length: counts.changed ?? 0 }, () => entry),
    license_changes: [],
    quality_samples: [
      {
        domains: ["web"],
        expansion: "Application Programming Interface",
        source_count: 1,
        term: "API"
      }
    ],
    removed: Array.from({ length: counts.removed ?? 0 }, () => entry),
    source
  };
}

describe("refresh report", () => {
  it("aggregates source delta counts, parser errors, and benchmarks", () => {
    const report = buildRefreshReport({
      benchmarks: benchmarkMetrics({ measured_requests: 1000, p95_ms: 42, target: "web-core" }),
      generatedAt: "2026-07-10T00:00:00.000Z",
      parserErrors: parserErrorSummaries({
        errors: [{ count: 2, message: "parse failed", source: "mdn" }]
      }),
      sources: [
        { deltaPath: "data/deltas/2026-07-10/mdn.json", summary: summary("mdn", { added: 2 }) },
        {
          deltaPath: "data/deltas/2026-07-10/aws.json",
          summary: summary("aws", { changed: 1, removed: 1 })
        }
      ]
    });
    const rendered = renderRefreshReport(report);

    expect(report.totals).toMatchObject({
      added: 2,
      changed: 1,
      parserErrors: 2,
      removed: 1
    });
    expect(rendered).toContain("| Parser errors | 2 |");
    expect(rendered).toContain("| p95_ms | 42 |");
    expect(rendered).toContain("| aws | 0 | 1 | 1 | 0 | API |");
  });

  it("normalizes parser error arrays", () => {
    expect(parserErrorSummaries([{ message: "bad row", source: "ietf" }])).toEqual([
      { count: 1, message: "bad row", source: "ietf" }
    ]);
  });
});
