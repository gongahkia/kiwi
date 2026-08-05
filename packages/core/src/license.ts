import spdxLicenseIds from "spdx-license-ids";
import { z } from "zod";

export const SPDX_LICENSE_IDS = spdxLicenseIds;

const spdxLicenseSet = new Set<string>(SPDX_LICENSE_IDS);

export const LicenseIdSchema = z.string().refine((license) => spdxLicenseSet.has(license), {
  message: "license must be a known SPDX license id"
});

export function isKnownSpdxLicense(license: string): boolean {
  return spdxLicenseSet.has(license);
}
