import type { RawEntry, ScraperPlugin } from "../scraper.js";

const sourceName = "jargon-file";
const sourceUrl = "https://www.gutenberg.org/files/3008/3008-0.txt";

export const jargonFileScraper: ScraperPlugin = {
  name: sourceName,
  license: "LicenseRef-Public-Domain",
  refresh_interval: "manual",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const text = await fetchText(sourceUrl);

    for (const entry of textToRawEntries(text, retrievedAt)) {
      yield entry;
    }
  }
};

export function textToRawEntries(text: string, retrievedAt: string): RawEntry[] {
  const start = text.indexOf("Node:0, Next:1TBS");
  const end = text.indexOf("Node:Appendix A");
  if (start < 0 || end < 0 || end <= start) {
    throw new Error("could not locate Jargon File lexicon");
  }

  return text
    .slice(start, end)
    .split(/\nNode:/)
    .map((block, index) => (index === 0 ? block : `Node:${block}`))
    .flatMap((block): RawEntry[] => {
      const term = block.match(/^Node:([^,\n]+)/)?.[1]?.trim() ?? "";
      if (!term || term.startsWith("=")) return [];
      const meaning = cleanText(definitionFromBlock(block, term));
      if (!meaning) return [];

      return [
        {
          domains: ["hacker culture", "programming"],
          expansion: term,
          meaning,
          sources: [
            {
              license: "LicenseRef-Public-Domain",
              publisher: "Jargon File",
              retrieved_at: retrievedAt,
              snippet: meaning,
              source_quality: "canonical",
              title: "The Jargon File, version 4.2.2",
              url: sourceUrl
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

function definitionFromBlock(block: string, term: string): string {
  const lines = block.split(/\r?\n/);
  let index = 0;
  while (index < lines.length && lines[index]?.trim()) index += 1;
  while (index < lines.length && !lines[index]?.trim()) index += 1;
  if (lineStartsWithTerm(lines[index] ?? "", term)) index += 1;
  return lines.slice(index).join("\n");
}

function lineStartsWithTerm(line: string, term: string): boolean {
  return cleanText(line).toLowerCase().startsWith(term.toLowerCase());
}

function cleanText(input: string): string {
  return input
    .replace(/\r/g, "")
    .replace(/`([^']+)'/g, "$1")
    .replace(/\(Lexicon Entries End Here\)/g, "")
    .replace(/\s+/g, " ")
    .trim();
}
