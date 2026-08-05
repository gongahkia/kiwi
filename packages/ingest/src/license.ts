import spdxLicenseIds from "spdx-license-ids";

const spdxLicenseSet = new Set<string>(spdxLicenseIds);
const localCompatibleLicenses = new Set(["LicenseRef-IETF-TLP-5.0", "LicenseRef-Public-Domain"]);
const incompatibleLicenses = new Set(["CC-BY-NC-ND-3.0", "CC-BY-NC-ND-4.0"]);

export class IncompatibleSourceLicenseError extends Error {
  constructor(license: string) {
    super(`incompatible source license: ${license}`);
    this.name = "IncompatibleSourceLicenseError";
  }
}

export class UnknownSourceLicenseError extends Error {
  constructor(license: string) {
    super(`unknown source license: ${license}`);
    this.name = "UnknownSourceLicenseError";
  }
}

export function assertCompatibleSourceLicense(license: string): void {
  if (!spdxLicenseSet.has(license) && !localCompatibleLicenses.has(license)) {
    throw new UnknownSourceLicenseError(license);
  }

  if (incompatibleLicenses.has(license)) {
    throw new IncompatibleSourceLicenseError(license);
  }
}
