import type { RawEntry, ScraperPlugin } from "../scraper.js";

type RfcIndexEntry = {
  docId: string;
  number: string;
  title: string;
};

const sourceName = "ietf-rfc-index";
const indexUrl = "https://www.rfc-editor.org/rfc/rfc-index.xml";
const infoBaseUrl = "https://www.rfc-editor.org/info/rfc";
const sourceLicense = "LicenseRef-IETF-TLP-5.0";

export const ietfRfcIndexScraper: ScraperPlugin = {
  name: sourceName,
  license: sourceLicense,
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const indexXml = await fetchText(indexUrl);

    for (const entry of indexToRawEntries(indexXml, retrievedAt)) {
      yield entry;
    }
  }
};

export function indexToRawEntries(indexXml: string, retrievedAt: string): RawEntry[] {
  return parseRfcEntries(indexXml).flatMap((entry): RawEntry[] => {
    const acronym = acronymFromTitle(entry.title);
    if (!acronym) return [];

    return [
      {
        domains: ["ietf", "rfc", "networking", "standards"],
        expansion: acronym.expansion,
        meaning: acronym.expansion,
        sources: [
          {
            license: sourceLicense,
            publisher: "RFC Editor",
            retrieved_at: retrievedAt,
            snippet: `${entry.docId}, Title: ${entry.title}`,
            source_quality: "canonical",
            title: `${entry.docId} Title`,
            url: `${infoBaseUrl}${entry.number}`
          }
        ],
        term: acronym.term,
        examples: [`${entry.docId}, Title`]
      }
    ];
  });
}

async function fetchText(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: { "user-agent": "wat-ingest/0.0 (https://github.com/wat/wat)" }
  });
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.text();
}

function parseRfcEntries(indexXml: string): RfcIndexEntry[] {
  return Array.from(indexXml.matchAll(/<rfc-entry>([\s\S]*?)<\/rfc-entry>/g), (match) => {
    const block = match[1] ?? "";
    const docId = readTag(block, "doc-id");
    return {
      docId,
      number: docId.replace(/^RFC/i, ""),
      title: cleanText(decodeXml(readTag(block, "title")))
    };
  }).filter((entry) => /^RFC\d+$/.test(entry.docId) && entry.title);
}

function acronymFromTitle(title: string): { expansion: string; term: string } | null {
  const match = title.match(/^(.+?)\s*\(([A-Z][A-Z0-9-]{1,15})\)$/);
  if (!match) return null;

  const term = cleanText(match[2] ?? "");
  const expansion = cleanExpansion(match[1] ?? "");
  if (!term || !expansion) return null;
  if (expansion.split(" ").length < 2) return null;
  return { expansion, term };
}

function cleanExpansion(input: string): string {
  const withoutArticle = cleanText(input)
    .replace(/^(?:a|an|the)\s+/i, "")
    .replace(/^[^A-Za-z0-9]+/, "")
    .replace(/\s*[:;,-]\s*$/, "");
  if (/[()]/.test(withoutArticle)) return "";

  const focused = focusTrailingPhrase(withoutArticle);
  const words = focused.split(" ");
  if (words.length > 8 || /\bwith\b/i.test(focused)) return "";
  return focused;
}

function focusTrailingPhrase(input: string): string {
  const parts = input.split(/\s+(?:for|of)\s+(?:the\s+)?/i);
  const lastPart = parts.at(-1) ?? input;
  return lastPart.split(" ").length >= 2 ? lastPart : input;
}

function readTag(block: string, tag: string): string {
  return block.match(new RegExp(`<${tag}>([\\s\\S]*?)<\\/${tag}>`))?.[1] ?? "";
}

function decodeXml(input: string): string {
  return input
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

function cleanText(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}
