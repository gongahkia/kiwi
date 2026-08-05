import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { checkSourceRegistry, scraperNamesFromRegistry } from "./source-registry.js";
import { scrapers } from "./scrapers/index.js";

const registryPath = fileURLToPath(new URL("../../../docs/sources.md", import.meta.url));

describe("source registry", () => {
  it("extracts scraper names from docs table rows", () => {
    expect(
      scraperNamesFromRegistry(
        [
          "| Scraper | Publisher | License | Refresh | Notes |",
          "| --- | --- | --- | --- | --- |",
          "| `aws-services` | AWS | Apache-2.0 | weekly | services |",
          "| MDN | CC-BY-SA-2.5 | https://developer.mozilla.org/ | seed |"
        ].join("\n")
      )
    ).toEqual(["aws-services"]);
  });

  it("fails closed for missing or unknown scraper rows", () => {
    expect(
      checkSourceRegistry("| `example` | wat | MIT | manual | fixture |\n", ["example"])
    ).toEqual({ extra: [], missing: [], ok: true });
    expect(
      checkSourceRegistry("| `unknown` | wat | MIT | manual | fixture |\n", ["example"])
    ).toEqual({ extra: ["unknown"], missing: ["example"], ok: false });
  });

  it("documents every implemented scraper", () => {
    const registry = readFileSync(registryPath, "utf8");
    const result = checkSourceRegistry(registry);

    expect(result).toEqual({ extra: [], missing: [], ok: true });
    expect(scraperNamesFromRegistry(registry)).toHaveLength(scrapers.size);
  });
});
