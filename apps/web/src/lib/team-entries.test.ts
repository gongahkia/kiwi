import { describe, expect, it } from "vitest";

import { teamEntries, teamEntriesCsv } from "./team-entries";

describe("team export helpers", () => {
  it("exports every team entry source in CSV", () => {
    const csv = teamEntriesCsv();

    expect(csv).toContain("team-example-cap");
    expect(csv).toContain("team-example-df");
    for (const entry of teamEntries) {
      for (const source of entry.sources) {
        expect(csv).toContain(source.url);
      }
    }
  });
});
