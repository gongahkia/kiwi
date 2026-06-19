import { describe, expect, it } from "vitest";

import { reciprocalRankFusion, type RankingSignal } from "./rrf.js";

const benchmark = [
  {
    expected: "cap-theorem",
    signals: [
      { items: [{ id: "cap-policy" }, { id: "cap-theorem" }], name: "bm25" },
      { items: [{ id: "cap-market" }, { id: "cap-theorem" }], name: "vector" },
      { items: [{ id: "cap-hat" }, { id: "cap-theorem" }], name: "trigram" }
    ]
  },
  {
    expected: "rest-api",
    signals: [
      { items: [{ id: "rest-break" }, { id: "rest-api" }], name: "bm25" },
      { items: [{ id: "rest-therapy" }, { id: "rest-api" }], name: "vector" },
      { items: [{ id: "rest-period" }, { id: "rest-api" }], name: "trigram" }
    ]
  },
  {
    expected: "sla-agreement",
    signals: [
      { items: [{ id: "sla-printing" }, { id: "sla-agreement" }], name: "bm25" },
      { items: [{ id: "sla-battery" }, { id: "sla-agreement" }], name: "vector" },
      { items: [{ id: "sla-school" }, { id: "sla-agreement" }], name: "trigram" }
    ]
  }
];

function top1HitRate(signalName: string): number {
  const hits = benchmark.filter((caseItem) => {
    const signal = caseItem.signals.find((item) => item.name === signalName);
    return signal?.items[0]?.id === caseItem.expected;
  });

  return hits.length / benchmark.length;
}

function fusedTop1HitRate(): number {
  const hits = benchmark.filter((caseItem) => {
    const [top] = reciprocalRankFusion(caseItem.signals as RankingSignal[]);
    return top?.id === caseItem.expected;
  });

  return hits.length / benchmark.length;
}

describe("reciprocalRankFusion", () => {
  it("outperforms any single signal on the benchmark", () => {
    const fused = fusedTop1HitRate();

    expect(fused).toBeGreaterThan(top1HitRate("bm25"));
    expect(fused).toBeGreaterThan(top1HitRate("vector"));
    expect(fused).toBeGreaterThan(top1HitRate("trigram"));
  });
});
