import { describe, expect, it } from "vitest";

import { isKnownSpdxLicense, LicenseIdSchema } from "./license.js";

describe("LicenseIdSchema", () => {
  it("accepts known SPDX license ids", () => {
    for (const license of ["MIT", "Apache-2.0", "BSD-3-Clause", "CC-BY-4.0"]) {
      expect(LicenseIdSchema.safeParse(license).success).toBe(true);
      expect(isKnownSpdxLicense(license)).toBe(true);
    }
  });

  it("rejects unknown license ids", () => {
    for (const license of ["MITish", "Apache 2", "unknown", ""]) {
      expect(LicenseIdSchema.safeParse(license).success).toBe(false);
      expect(isKnownSpdxLicense(license)).toBe(false);
    }
  });
});
