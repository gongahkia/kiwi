import { describe, expect, it } from "vitest";

import { normalizeTerm } from "./normalize.js";

const cases: Array<[string, string]> = [
  ["CAP", "cap"],
  ["  CAP   theorem  ", "cap theorem"],
  ["C.A.P.", "c a p"],
  ["SLA/SLO", "sla slo"],
  ["REST-ish", "rest ish"],
  ["OAuth 2.0", "oauth 2 0"],
  ["Kubernetes", "kubernetes"],
  ["k8s", "k8s"],
  ["Résumé", "resume"],
  ["naïve café", "naive cafe"],
  ["São Paulo", "sao paulo"],
  ["München", "munchen"],
  ["crème brûlée", "creme brulee"],
  ["full\ttext\nsearch", "full text search"],
  ["CI/CD", "ci cd"],
  ["PostgreSQL: pg_trgm", "postgresql pg trgm"],
  ["vector(384)", "vector 384"],
  ["hello_world", "hello world"],
  ["C++", "c"],
  ["  --API!! Gateway??  ", "api gateway"]
];

describe("normalizeTerm", () => {
  it.each(cases)("%s -> %s", (input, expected) => {
    expect(normalizeTerm(input)).toBe(expected);
  });
});
