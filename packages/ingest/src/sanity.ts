import type { CanonicalSourceCitation } from "./transform.js";
import { normalizeDisplayTerm, normalizeDisplayTermKey } from "./normalize.js";

export interface LintableEntry {
  confidence_tier?: string;
  id?: string;
  layer?: string;
  contemporaries?: string[];
  sources?: CanonicalSourceCitation[];
  term?: string;
}

export interface SanityIssue {
  code:
    | "contemporary_duplicate"
    | "contemporary_empty"
    | "contemporary_self_reference"
    | "missing_public_source"
    | "t1_without_canonical_source";
  entry_id: string;
}

function entryId(entry: LintableEntry, index: number): string {
  return entry.id ?? entry.term ?? `entry-${index}`;
}

export function lintEntries(entries: LintableEntry[]): SanityIssue[] {
  return entries.flatMap((entry, index): SanityIssue[] => {
    const issues: SanityIssue[] = [];
    const sources = entry.sources ?? [];
    const id = entryId(entry, index);
    const isPublic = !entry.layer || entry.layer === "public";

    if (isPublic && sources.length === 0) {
      issues.push({ code: "missing_public_source", entry_id: id });
    }

    if (
      entry.confidence_tier === "T1" &&
      !sources.some((source) => source.source_quality === "canonical")
    ) {
      issues.push({ code: "t1_without_canonical_source", entry_id: id });
    }

    const contemporaryKeys = new Set<string>();
    const termKey = entry.term ? normalizeDisplayTermKey(entry.term) : "";
    for (const contemporary of entry.contemporaries ?? []) {
      const normalized = normalizeDisplayTerm(contemporary);
      const key = normalizeDisplayTermKey(contemporary);
      if (!normalized) {
        issues.push({ code: "contemporary_empty", entry_id: id });
        continue;
      }
      if (termKey && key === termKey) {
        issues.push({ code: "contemporary_self_reference", entry_id: id });
      }
      if (contemporaryKeys.has(key)) {
        issues.push({ code: "contemporary_duplicate", entry_id: id });
      }
      contemporaryKeys.add(key);
    }

    return issues;
  });
}
