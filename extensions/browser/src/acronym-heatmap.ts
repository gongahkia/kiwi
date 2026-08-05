export interface AcronymDensity {
  count: number;
  level: 0 | 1 | 2 | 3;
  ratio: number;
  words: number;
}

const acronymPattern = /\b[A-Z][A-Z0-9]{1,9}\b/g;

export function acronymDensityForText(text: string): AcronymDensity {
  const count = text.match(acronymPattern)?.length ?? 0;
  const words = text.trim().split(/\s+/).filter(Boolean).length;
  const ratio = count / Math.max(words, 1);
  return {
    count,
    level: densityLevel(count, ratio),
    ratio,
    words
  };
}

export function heatmapAlpha(level: AcronymDensity["level"]): string {
  return ["0", "0.1", "0.18", "0.26"][level] ?? "0";
}

function densityLevel(count: number, ratio: number): AcronymDensity["level"] {
  if (count === 0) return 0;
  if (count >= 8 || ratio >= 0.18) return 3;
  if (count >= 4 || ratio >= 0.1) return 2;
  return 1;
}
