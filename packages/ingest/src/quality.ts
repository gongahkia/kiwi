import type { RawEntry } from "./scraper.js";

export interface RejectedRawEntry {
  entry: RawEntry;
  reason: "missing_expansion" | "term_too_short" | "expansion_too_short";
}

export interface RawEntryFilterResult {
  accepted: RawEntry[];
  rejected: RejectedRawEntry[];
}

export function rejectReason(entry: RawEntry): RejectedRawEntry["reason"] | null {
  if (!entry.expansion?.trim()) {
    return "missing_expansion";
  }

  if (entry.term.trim().length < 2) {
    return "term_too_short";
  }

  if (entry.expansion.trim().length < 2) {
    return "expansion_too_short";
  }

  return null;
}

export function filterGarbageRawEntries(entries: RawEntry[]): RawEntryFilterResult {
  const accepted: RawEntry[] = [];
  const rejected: RejectedRawEntry[] = [];

  for (const entry of entries) {
    const reason = rejectReason(entry);
    if (reason) {
      rejected.push({ entry, reason });
    } else {
      accepted.push(entry);
    }
  }

  return { accepted, rejected };
}
