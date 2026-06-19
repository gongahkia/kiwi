import { describe, expect, it } from "vitest";

import {
  assertCompatibleSourceLicense,
  IncompatibleSourceLicenseError,
  UnknownSourceLicenseError
} from "./license.js";
import { transformRawEntry } from "./transform.js";

describe("source license validation", () => {
  it("allows known compatible SPDX licenses", () => {
    expect(() => assertCompatibleSourceLicense("MIT")).not.toThrow();
    expect(() => assertCompatibleSourceLicense("CC-BY-4.0")).not.toThrow();
  });

  it("allows the local public-domain source marker", () => {
    expect(() => assertCompatibleSourceLicense("LicenseRef-Public-Domain")).not.toThrow();
  });

  it("allows the IETF Trust Legal Provisions source marker", () => {
    expect(() => assertCompatibleSourceLicense("LicenseRef-IETF-TLP-5.0")).not.toThrow();
  });

  it("rejects unknown licenses", () => {
    expect(() => assertCompatibleSourceLicense("unknown")).toThrow(UnknownSourceLicenseError);
  });

  it("rejects incompatible licenses", () => {
    expect(() => assertCompatibleSourceLicense("CC-BY-NC-ND-4.0")).toThrow(
      IncompatibleSourceLicenseError
    );
  });

  it("fails transform when a source license is unknown", () => {
    expect(() =>
      transformRawEntry({
        expansion: "Bad License",
        sources: [
          {
            license: "unknown",
            publisher: "Example",
            retrieved_at: "2026-01-01T00:00:00.000Z",
            url: "https://example.com/bad"
          }
        ],
        term: "BAD"
      })
    ).toThrow(UnknownSourceLicenseError);
  });
});
