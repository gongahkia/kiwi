export interface VectorCandidate {
  embedding: number[];
  id: string;
}

export interface VectorMatch extends VectorCandidate {
  score: number;
}

export function cosineSimilarity(left: number[], right: number[]): number {
  const length = Math.min(left.length, right.length);
  let dot = 0;
  let leftMagnitude = 0;
  let rightMagnitude = 0;

  for (let index = 0; index < length; index += 1) {
    const leftValue = left[index] ?? 0;
    const rightValue = right[index] ?? 0;
    dot += leftValue * rightValue;
    leftMagnitude += leftValue ** 2;
    rightMagnitude += rightValue ** 2;
  }

  if (leftMagnitude === 0 || rightMagnitude === 0) {
    return 0;
  }

  return dot / (Math.sqrt(leftMagnitude) * Math.sqrt(rightMagnitude));
}

export function rankByVector(query: number[], candidates: VectorCandidate[]): VectorMatch[] {
  return candidates
    .map((candidate) => ({
      ...candidate,
      score: cosineSimilarity(query, candidate.embedding)
    }))
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id));
}
