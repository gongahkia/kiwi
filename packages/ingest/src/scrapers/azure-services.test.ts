import { describe, expect, it } from "vitest";

import { readmeToRawEntry } from "./azure-services.js";

describe("azure services scraper", () => {
  it("maps Azure REST API readme headings to service-name entries", () => {
    const entry = readmeToRawEntry(
      "storage",
      "specification/storage/resource-manager/readme.md",
      "# Storage\n\nThis is the AutoRest configuration file for Storage.",
      "2026-06-19T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["azure", "cloud", "service names"],
      expansion: "Storage",
      meaning: "Storage",
      term: "storage"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "MIT",
      publisher: "Azure REST API Specs",
      source_quality: "canonical",
      url: "https://github.com/Azure/azure-rest-api-specs/blob/main/specification/storage/resource-manager/readme.md"
    });
  });
});
