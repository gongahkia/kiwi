export interface TeamEntrySource {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  title: string;
  url: string;
}

export interface TeamEntry {
  contemporaries?: string[];
  domains: string[];
  expansion: string;
  id: string;
  meaning: string;
  sources: TeamEntrySource[];
  term: string;
}

const privateSourceLicenses = new Set([
  "internal",
  "proprietary-personal",
  "proprietary-team",
  "unknown"
]);

function nonEmpty(value: string): boolean {
  return value.trim().length > 0;
}

function validUrl(value: string): boolean {
  try {
    new URL(value);
    return true;
  } catch {
    return false;
  }
}

function isGeneratedSourceUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.hostname === "wat.local";
  } catch {
    return false;
  }
}

function validateSource(source: unknown): string | null {
  if (!source || typeof source !== "object") return "source fields are required";
  const candidate = source as Partial<TeamEntrySource>;
  const sourceValues = [
    candidate.license,
    candidate.publisher,
    candidate.retrieved_at,
    candidate.snippet,
    candidate.title,
    candidate.url
  ];
  if (sourceValues.some((value) => typeof value !== "string" || !nonEmpty(value))) {
    return "source fields are required";
  }
  if (!validUrl(candidate.url!)) return "source url must be valid";
  if (Number.isNaN(Date.parse(candidate.retrieved_at!))) {
    return "source retrieved_at must be valid";
  }
  if (!privateSourceLicenses.has(candidate.license!) && isGeneratedSourceUrl(candidate.url!)) {
    return "public-compatible source license requires an external source url";
  }
  return null;
}

export function validateTeamEntry(entry: TeamEntry): string[] {
  const issues: string[] = [];
  if (!nonEmpty(entry.id)) issues.push("id is required");
  if (!nonEmpty(entry.term)) issues.push("term is required");
  if (!nonEmpty(entry.expansion)) issues.push("expansion is required");
  if (!nonEmpty(entry.meaning)) issues.push("meaning is required");
  if (entry.domains.length === 0) issues.push("at least one domain is required");
  if (!entry.domains.every(nonEmpty)) issues.push("domains are required");
  if (entry.contemporaries && !Array.isArray(entry.contemporaries)) {
    issues.push("contemporaries must be a string array");
  } else if (entry.contemporaries && !entry.contemporaries.every(nonEmpty)) {
    issues.push("contemporaries are required");
  }
  if (entry.sources.length === 0) issues.push("at least one source is required");
  for (const [index, source] of entry.sources.entries()) {
    const issue = validateSource(source);
    if (issue) issues.push(`source ${index}: ${issue}`);
  }
  return issues;
}
