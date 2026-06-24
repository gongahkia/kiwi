import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { confidenceLabel, layerLabel } from "@/lib/search-result-labels";

const renderedFieldFiles = [
  join(process.cwd(), "src/components/search-result-card.tsx"),
  join(process.cwd(), "src/components/team-entry-crud.tsx"),
  join(process.cwd(), "src/components/suggest-entry-form.tsx"),
  join(process.cwd(), "src/components/suggest-edit-form.tsx")
];

describe("search result card labels", () => {
  it("explains every result layer", () => {
    expect(layerLabel("public")).toBe("Public source");
    expect(layerLabel("team")).toBe("Team entry");
    expect(layerLabel("personal")).toBe("Personal entry");
  });

  it("explains confidence and pending states", () => {
    expect(confidenceLabel("T1")).toBe("High confidence");
    expect(confidenceLabel("T2")).toBe("Verified");
    expect(confidenceLabel("T3")).toBe("Low confidence");
    expect(confidenceLabel("T4")).toBe("Pending review");
  });

  it("does not use raw HTML sinks for user-provided glossary fields", () => {
    for (const file of renderedFieldFiles) {
      const source = readFileSync(file, "utf8");

      expect(source).not.toContain("dangerouslySetInnerHTML");
      expect(source).not.toMatch(/\binnerHTML\b|\binsertAdjacentHTML\b|\bouterHTML\b/);
    }
  });

  it("covers field render sites for term, expansion, meaning, source, and domains", () => {
    const source = renderedFieldFiles.map((file) => readFileSync(file, "utf8")).join("\n");

    expect(source).toContain("entry.term");
    expect(source).toContain("entry.expansion");
    expect(source).toContain("entry.meaning");
    expect(source).toContain("entry.domains");
    expect(source).toContain("entry.sources");
  });
});
