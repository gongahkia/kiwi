import type { RawEntry, ScraperPlugin } from "../scraper.js";

type FossAcronymRecord = {
  Abbreviation?: string;
  Definition?: string;
  Example?: string;
  Meaning?: string;
  URL?: string;
  Usage?: string;
  "What they do"?: string;
};

const sourceName = "d-edge-foss-acronyms";
const baseUrl = "https://raw.githubusercontent.com/d-edge/foss-acronyms/main/data";
const files = ["acronyms", "chat-acronyms", "design-patterns", "organizations", "stacks"] as const;
const domainByFile: Record<(typeof files)[number], string[]> = {
  acronyms: ["foss"],
  "chat-acronyms": ["chat"],
  "design-patterns": ["software architecture"],
  organizations: ["organizations"],
  stacks: ["tech stacks"]
};

export const dEdgeFossAcronymsScraper: ScraperPlugin = {
  name: sourceName,
  license: "CC0-1.0",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();

    for (const file of files) {
      const records = (await fetchJson(`${baseUrl}/${file}.json`)) as FossAcronymRecord[];
      for (const entry of recordsToRawEntries(file, records, retrievedAt)) {
        yield entry;
      }
    }
  }
};

export function recordsToRawEntries(
  file: (typeof files)[number],
  records: FossAcronymRecord[],
  retrievedAt: string
): RawEntry[] {
  const sourceUrl = `${baseUrl}/${file}.json`;

  return records.flatMap((record): RawEntry[] => {
    const term = cleanText(record.Abbreviation ?? "");
    const expansion = cleanText(record.Definition ?? record.Meaning ?? "");
    if (!term || !expansion) return [];

    const usage = cleanText(record.Usage ?? record["What they do"] ?? "") || expansion;
    const example = cleanText(record.Example ?? record.URL ?? "");

    return [
      {
        domains: domainByFile[file],
        examples: example ? [example] : [],
        expansion,
        meaning: usage,
        sources: [
          {
            license: "CC0-1.0",
            publisher: "d-edge/foss-acronyms",
            retrieved_at: retrievedAt,
            snippet: usage,
            source_quality: "community",
            title: `d-edge/foss-acronyms ${file}.json`,
            url: sourceUrl
          }
        ],
        term
      }
    ];
  });
}

async function fetchJson(url: string): Promise<unknown> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.json();
}

function cleanText(input: string): string {
  return input
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}
