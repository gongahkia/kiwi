import { describe, expect, it } from "vitest";

import { rankByTrigram, trigramSimilarity } from "./trigram.js";

describe("rankByTrigram", () => {
  it("ranks Kubernetes top-3 for kuberntes typo", () => {
    const matches = rankByTrigram("kuberntes", [
      { id: "postgres", term: "PostgreSQL" },
      { id: "kubernetes", term: "Kubernetes" },
      { id: "kafka", term: "Kafka" },
      { id: "kubectl", term: "kubectl" },
      { id: "kubelet", term: "kubelet" }
    ]);

    expect(matches.slice(0, 3).map((match) => match.id)).toContain("kubernetes");
  });

  it("scores exact matches above typos", () => {
    expect(trigramSimilarity("kubernetes", "kubernetes")).toBeGreaterThan(
      trigramSimilarity("kuberntes", "kubernetes")
    );
  });
});
