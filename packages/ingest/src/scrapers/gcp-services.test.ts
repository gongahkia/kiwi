import { describe, expect, it } from "vitest";

import { sourceToRawEntry } from "./gcp-services.js";

describe("gcp services scraper", () => {
  it("maps generated client source to service-name entries", () => {
    const entry = sourceToRawEntry(
      "src/apis/compute/v1.ts",
      `
      /**
       * Compute Engine API
       *
       * Creates and runs virtual machines on Google Cloud Platform.
       *
       * @example
       */
      export class Compute {
      }
      `,
      "2026-06-19T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["gcp", "google cloud", "service names"],
      expansion: "Compute Engine API",
      meaning: "Creates and runs virtual machines on Google Cloud Platform.",
      term: "compute"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "Apache-2.0",
      publisher: "Google API Node.js Client",
      source_quality: "canonical",
      url: "https://github.com/googleapis/google-api-nodejs-client/blob/main/src/apis/compute/v1.ts"
    });
  });
});
