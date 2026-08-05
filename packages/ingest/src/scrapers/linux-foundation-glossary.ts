import type { RawEntry, ScraperPlugin } from "../scraper.js";

type GlossaryRow = {
  definition: string;
  relatedTerms: string[];
  term: string;
};

const sourceName = "linux-foundation-glossary";
const tsvUrl =
  "https://raw.githubusercontent.com/State-of-the-Edge/glossary/master/edge-glossary.tsv";
const sourceUrl = "https://github.com/State-of-the-Edge/glossary/blob/master/edge-glossary.tsv";

export const linuxFoundationGlossaryScraper: ScraperPlugin = {
  name: sourceName,
  license: "CC-BY-SA-4.0",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const tsv = await fetchText(tsvUrl);

    for (const entry of tsvToRawEntries(tsv, retrievedAt)) {
      yield entry;
    }
  }
};

export function tsvToRawEntries(tsv: string, retrievedAt: string): RawEntry[] {
  return parseRows(tsv).flatMap((row): RawEntry[] => {
    if (!row.term || !row.definition) return [];

    return [
      {
        domains: ["linux foundation", "lf edge", "edge computing"],
        expansion: row.term,
        meaning: row.definition,
        sources: [
          {
            license: "CC-BY-SA-4.0",
            publisher: "LF Edge Open Glossary of Edge Computing",
            retrieved_at: retrievedAt,
            snippet: row.definition,
            source_quality: "canonical",
            title: `LF Edge Open Glossary: ${row.term}`,
            url: sourceUrl
          }
        ],
        term: row.term,
        examples: row.relatedTerms.length > 0 ? [`See also: ${row.relatedTerms.join(", ")}`] : []
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

function parseRows(tsv: string): GlossaryRow[] {
  const [, ...lines] = tsv.replace(/\r\n/g, "\n").trim().split("\n");
  return lines.map((line) => {
    const [term = "", definition = "", ...related] = line.split("\t");
    return {
      definition: cleanText(definition),
      relatedTerms: related.map(cleanText).filter(Boolean),
      term: cleanText(term)
    };
  });
}

function cleanText(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}
