export interface InventorySource {
  license: string;
  publisher: string;
  retrieved_at: string;
  title: string;
  url: string;
}

export interface InventoryEntry {
  layer: string;
  sources: InventorySource[];
}

export interface SourceInventoryRow extends InventorySource {
  count: number;
  failure_status: string;
  license_policy: string;
}

function licensePolicy(license: string): string {
  if (license.startsWith("LicenseRef-")) return "approved local license policy";
  if (license.includes("-NC-") || license.includes("-ND-")) return "manual review required";
  return "compatible public corpus license";
}

function validDate(value: string): boolean {
  return !Number.isNaN(Date.parse(value));
}

function validUrl(value: string): boolean {
  try {
    new URL(value);
    return true;
  } catch {
    return false;
  }
}

function failureStatus(source: InventorySource, count: number): string {
  if (count < 1) return "no entries";
  if (!validUrl(source.url)) return "invalid source url";
  if (!validDate(source.retrieved_at)) return "invalid retrieved_at";
  return "ok";
}

export function sourceInventoryFromEntries(entries: InventoryEntry[]): SourceInventoryRow[] {
  const byUrl = new Map<string, SourceInventoryRow>();

  for (const entry of entries.filter((candidate) => candidate.layer === "public")) {
    for (const source of entry.sources) {
      const existing = byUrl.get(source.url);
      const count = (existing?.count ?? 0) + 1;
      const retrievedAt =
        existing && existing.retrieved_at > source.retrieved_at
          ? existing.retrieved_at
          : source.retrieved_at;
      const row = {
        ...source,
        count,
        retrieved_at: retrievedAt,
        license_policy: licensePolicy(source.license)
      };
      byUrl.set(source.url, {
        ...row,
        failure_status: failureStatus(row, count)
      });
    }
  }

  return [...byUrl.values()].sort((left, right) => left.publisher.localeCompare(right.publisher));
}
