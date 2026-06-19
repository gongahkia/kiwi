export const ACRONYM_PATTERN =
  /\b(?:[A-Z]{2,}(?:[/-][A-Z0-9]{2,})*|[A-Z]+[a-z]*\d+[A-Za-z0-9]*|[a-z]\d+[a-z]|[a-z]\d+[a-z]\d*[a-z]*)\b/g;

export function detectAcronyms(input: string): string[] {
  return Array.from(input.matchAll(ACRONYM_PATTERN), (match) => match[0]);
}
