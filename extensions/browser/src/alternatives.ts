export function listAlternatives(values?: string[]): string[] {
  const seen = new Set<string>();
  const alternatives: string[] = [];
  for (const value of values ?? []) {
    const alternative = value.trim();
    if (!alternative) continue;
    const key = alternative.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    alternatives.push(alternative);
  }
  return alternatives;
}

export function formatAlternativesLine(values?: string[], limit = 3): string | null {
  const alternatives = listAlternatives(values);
  if (alternatives.length === 0) return null;

  const visible = alternatives.slice(0, limit);
  const hidden = alternatives.length - visible.length;
  return `Alt: ${visible.join(", ")}${hidden > 0 ? `, +${hidden} more` : ""}`;
}
