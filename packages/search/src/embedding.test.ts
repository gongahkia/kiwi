import { describe, expect, it } from "vitest";

import { toFloat32Vector } from "./embedding.js";

describe("toFloat32Vector", () => {
  it("preserves Float32Array vectors", () => {
    const vector = new Float32Array([1, 2, 3]);

    expect(toFloat32Vector(vector)).toBe(vector);
  });

  it("converts iterable vectors", () => {
    expect(toFloat32Vector([1, 2, 3])).toBeInstanceOf(Float32Array);
  });
});
