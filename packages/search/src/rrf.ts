export interface RankedItem {
  id: string;
}

export interface RankingSignal {
  items: RankedItem[];
  name: string;
  weight?: number;
}

export interface FusedRankedItem {
  id: string;
  score: number;
}

export function reciprocalRankFusion(signals: RankingSignal[], k = 60): FusedRankedItem[] {
  const scores = new Map<string, number>();

  for (const signal of signals) {
    const weight = signal.weight ?? 1;
    signal.items.forEach((item, index) => {
      const rank = index + 1;
      scores.set(item.id, (scores.get(item.id) ?? 0) + weight / (k + rank));
    });
  }

  return Array.from(scores.entries())
    .map(([id, score]) => ({ id, score }))
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id));
}
