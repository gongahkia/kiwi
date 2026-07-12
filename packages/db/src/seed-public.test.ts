import { describe, expect, it } from "vitest";

import { readLatestReviewedDeltas, readPublicCorpusEntries } from "./seed-public.js";

describe("public corpus loader", () => {
  it("loads the latest checked-in delta for every non-fixture source", async () => {
    const deltas = await readLatestReviewedDeltas();

    expect(deltas.map((delta) => delta.source)).toEqual(
      expect.arrayContaining([
        "aws-services",
        "azure-services",
        "cncf-glossary",
        "contemporaries-seed",
        "gcp-services",
        "kubernetes-glossary",
        "postgresql-glossary"
      ])
    );
    expect(deltas.some((delta) => delta.source === "example")).toBe(false);
  });

  it("makes the reviewed corpus substantially larger than the manual demo seed", async () => {
    const entries = await readPublicCorpusEntries();

    expect(entries.length).toBeGreaterThan(10_000);
    expect(entries.some((entry) => entry.term === "AccessAnalyzer")).toBe(true);
    expect(entries.some((entry) => entry.term === "Kubernetes")).toBe(true);
  });
});
