export function normalizeDisplayTerm(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}

export function normalizeDisplayTermKey(input: string): string {
  return normalizeDisplayTerm(input).toLowerCase();
}

export function normalizeDisplayTermList(input: string[]): string[] {
  const seen = new Set<string>();
  const output: string[] = [];

  for (const value of input) {
    const normalized = normalizeDisplayTerm(value);
    if (!normalized) {
      continue;
    }

    const key = normalizeDisplayTermKey(normalized);
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    output.push(normalized);
  }

  return output;
}
