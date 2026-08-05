import type { CanonicalEntry } from "./transform.js";

function levenshtein(left: string, right: string): number {
  const previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  const current = Array.from({ length: right.length + 1 }, () => 0);

  for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    current[0] = leftIndex;
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      const cost = left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1;
      current[rightIndex] = Math.min(
        (current[rightIndex - 1] ?? 0) + 1,
        (previous[rightIndex] ?? 0) + 1,
        (previous[rightIndex - 1] ?? 0) + cost
      );
    }
    previous.splice(0, previous.length, ...current);
  }

  return previous[right.length] ?? 0;
}

export function fuzzySimilarity(left: string, right: string): number {
  const maxLength = Math.max(left.length, right.length);
  if (maxLength === 0) {
    return 1;
  }

  return 1 - levenshtein(left, right) / maxLength;
}

export function dedupCanonicalEntries(
  entries: CanonicalEntry[],
  fuzzyThreshold = 0.94
): CanonicalEntry[] {
  const unique: CanonicalEntry[] = [];

  for (const entry of entries) {
    const duplicate = unique.some(
      (candidate) =>
        candidate.dedup_key === entry.dedup_key ||
        (candidate.term_normalized === entry.term_normalized &&
          fuzzySimilarity(candidate.expansion_normalized, entry.expansion_normalized) >=
            fuzzyThreshold)
    );

    if (!duplicate) {
      unique.push(entry);
    }
  }

  return unique;
}
