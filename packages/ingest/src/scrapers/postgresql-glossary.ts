import type { RawEntry, ScraperPlugin } from "../scraper.js";

const sourceName = "postgresql-glossary";
const glossaryUrl = "https://www.postgresql.org/docs/current/glossary.html";

export const postgresqlGlossaryScraper: ScraperPlugin = {
  name: sourceName,
  license: "PostgreSQL",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const html = await fetchText(glossaryUrl);

    for (const entry of htmlToRawEntries(html, retrievedAt)) {
      yield entry;
    }
  }
};

export function htmlToRawEntries(html: string, retrievedAt: string): RawEntry[] {
  const matches = html.matchAll(
    /<dt(?: id="([^"]+)")?[^>]*>([\s\S]*?)<\/dt>\s*<dd[^>]*>([\s\S]*?)<\/dd>/g
  );

  return Array.from(matches).flatMap((match): RawEntry[] => {
    const [, id = "", termHtml = "", definitionHtml = ""] = match;
    const term = cleanHtml(termHtml);
    const meaning = cleanHtml(definitionHtml);
    if (!term || !meaning) return [];

    return [
      {
        domains: ["postgresql", "database"],
        expansion: expansionFromDefinition(term, meaning),
        meaning,
        sources: [
          {
            license: "PostgreSQL",
            publisher: "PostgreSQL Documentation",
            retrieved_at: retrievedAt,
            snippet: meaning,
            source_quality: "canonical",
            title: `PostgreSQL glossary: ${term}`,
            url: id ? `${glossaryUrl}#${id}` : glossaryUrl
          }
        ],
        term
      }
    ];
  });
}

async function fetchText(url: string): Promise<string> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.text();
}

function expansionFromDefinition(term: string, meaning: string): string {
  if (!/^[A-Z][A-Z0-9/ -]+$/.test(term)) return term;
  const [firstSentence = term] = meaning.split(".");
  return firstSentence.length <= 160 ? firstSentence : term;
}

function cleanHtml(input: string): string {
  return input
    .replace(/<a[^>]*><\/a>/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:])/g, "$1")
    .trim();
}
