import { describe, expect, it } from "vitest";

import { formatAlternativesLine, listAlternatives } from "./alternatives.js";

describe("alternatives", () => {
  it("normalizes alternatives", () => {
    expect(listAlternatives([" SSR ", "", "ssr", "MPA"])).toEqual(["SSR", "MPA"]);
  });

  it("formats compact hover text", () => {
    expect(formatAlternativesLine(["SSR", "MPA", "ISR"])).toBe("Alt: SSR, MPA, ISR");
    expect(formatAlternativesLine(["SSR", "MPA", "ISR", "CSR"])).toBe(
      "Alt: SSR, MPA, ISR, +1 more"
    );
  });

  it("omits empty hover text", () => {
    expect(formatAlternativesLine([])).toBeNull();
  });
});
