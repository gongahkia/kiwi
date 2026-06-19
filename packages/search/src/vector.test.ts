import { describe, expect, it } from "vitest";

import { cosineSimilarity, rankByVector } from "./vector.js";

function basis(index: number): number[] {
  return Array.from({ length: 20 }, (_, current) => (current === index ? 1 : 0));
}

describe("rankByVector", () => {
  it("returns ranked entries by cosine for 20 fixtures", () => {
    const candidates = Array.from({ length: 20 }, (_, index) => ({
      embedding: basis(index),
      id: `entry-${index}`
    }));

    for (let index = 0; index < 20; index += 1) {
      const [top] = rankByVector(basis(index), candidates);
      expect(top?.id).toBe(`entry-${index}`);
      expect(top?.score).toBe(1);
    }
  });

  it("returns 0 when either vector is zero", () => {
    expect(cosineSimilarity([0, 0], [1, 0])).toBe(0);
  });
});
