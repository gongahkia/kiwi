import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const renderFiles = [
  new URL("../entrypoints/content.ts", import.meta.url),
  new URL("../entrypoints/sidepanel/main.ts", import.meta.url)
];

describe("browser extension XSS regressions", () => {
  it("renders glossary data through textContent, not HTML sinks", () => {
    for (const file of renderFiles) {
      const source = readFileSync(file, "utf8");

      expect(source).not.toMatch(/\binnerHTML\b|\binsertAdjacentHTML\b|\bouterHTML\b/);
      expect(source).toContain("textContent");
    }
  });

  it("covers term, expansion, meaning, source, and alternatives render assignments", () => {
    const content = readFileSync(renderFiles[0]!, "utf8");
    const sidepanel = readFileSync(renderFiles[1]!, "utf8");

    expect(content).toContain("title.textContent");
    expect(content).toContain("meaning.textContent");
    expect(content).toContain("sourceLine.textContent");
    expect(sidepanel).toContain("title.textContent");
    expect(sidepanel).toContain("meaning.textContent");
    expect(sidepanel).toContain("meta.textContent");
    expect(sidepanel).toContain("button.textContent");
  });
});
