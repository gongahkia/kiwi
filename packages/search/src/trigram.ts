export interface TrigramCandidate {
  id: string;
  term: string;
}

export interface TrigramMatch extends TrigramCandidate {
  score: number;
}

function trigrams(input: string): Set<string> {
  const normalized = `  ${input.toLowerCase().replace(/\s+/g, " ")} `;
  const values = new Set<string>();
  for (let index = 0; index <= normalized.length - 3; index += 1) {
    values.add(normalized.slice(index, index + 3));
  }
  return values;
}

export function trigramSimilarity(left: string, right: string): number {
  const leftTrigrams = trigrams(left);
  const rightTrigrams = trigrams(right);
  const intersection = Array.from(leftTrigrams).filter((item) => rightTrigrams.has(item)).length;
  const union = new Set([...leftTrigrams, ...rightTrigrams]).size;

  return union === 0 ? 0 : intersection / union;
}

export function rankByTrigram(query: string, candidates: TrigramCandidate[]): TrigramMatch[] {
  return candidates
    .map((candidate) => ({
      ...candidate,
      score: trigramSimilarity(query, candidate.term)
    }))
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id));
}
