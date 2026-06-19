import { describe, expect, it } from "vitest";

import { evaluateBenchmarkGate } from "./benchmark-gate.js";

describe("evaluateBenchmarkGate", () => {
  it("passes when hit-rate drift stays within 1pp", () => {
    expect(
      evaluateBenchmarkGate(
        { top_1_hit_rate: 0.957, top_5_hit_rate: 0.989 },
        { top_1_hit_rate: 0.966, top_5_hit_rate: 0.998 }
      )
    ).toEqual({ failures: [], ok: true });
  });

  it("fails when hit-rate drops more than 1pp", () => {
    const result = evaluateBenchmarkGate(
      { top_1_hit_rate: 0.955, top_5_hit_rate: 0.987 },
      { top_1_hit_rate: 0.966, top_5_hit_rate: 0.998 }
    );

    expect(result.ok).toBe(false);
    expect(result.failures).toEqual([
      "top_1_hit_rate dropped 1.10pp",
      "top_5_hit_rate dropped 1.10pp"
    ]);
  });
});
