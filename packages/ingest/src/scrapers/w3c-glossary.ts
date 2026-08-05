import type { RawEntry, ScraperPlugin } from "../scraper.js";

const sourceName = "w3c-glossary";
const alphaBaseUrl = "https://www.w3.org/2003/glossary/alpha";
const glossaryUrl = `${alphaBaseUrl}/A/`;
const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".replace("Y", "").split("");

export const w3cGlossaryScraper: ScraperPlugin = {
  name: sourceName,
  license: "W3C",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();

    for (const letter of letters) {
      let nextUrl: string | null = `${alphaBaseUrl}/${letter}/`;
      while (nextUrl) {
        const html = await fetchText(nextUrl, {
          allowMissing: nextUrl !== `${alphaBaseUrl}/${letter}/`
        });
        if (!html) break;
        for (const entry of htmlToRawEntries(html, retrievedAt, nextUrl)) {
          yield entry;
        }
        nextUrl = nextPageUrl(html, nextUrl);
      }
    }
  }
};

export function htmlToRawEntries(
  html: string,
  retrievedAt: string,
  pageUrl = glossaryUrl
): RawEntry[] {
  const matches = html.matchAll(
    /<dt>\s*<a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>\s*<\/dt>\s*<dd>([\s\S]*?)<\/dd>/g
  );

  return Array.from(matches).flatMap((match): RawEntry[] => {
    const [, keywordHref = "", termHtml = "", ddHtml = ""] = match;
    const termText = cleanHtml(termHtml);
    const definitionHtml = ddHtml.match(/<div class="definition">([\s\S]*?)<\/div>/)?.[1] ?? "";
    const meaning = cleanHtml(definitionHtml);
    if (!termText || !meaning) return [];

    const detail = sourceDetail(ddHtml);
    const { term, expansion } = splitTermExpansion(termText);
    const sourceTitle = detail.title || "W3C Glossary and Dictionary";

    return [
      {
        domains: ["w3c", "web standards"],
        expansion,
        meaning,
        sources: [
          {
            license: "W3C",
            publisher: "W3C Glossary and Dictionary",
            retrieved_at: retrievedAt,
            snippet: meaning,
            source_quality: "canonical",
            title: `W3C glossary: ${term} (${sourceTitle})`,
            url: new URL(keywordHref, pageUrl).toString()
          }
        ],
        term
      }
    ];
  });
}

export function nextPageUrl(html: string, pageUrl = glossaryUrl): string | null {
  const href = html.match(/<a href="([^"]+)" rel="next"/)?.[1];
  return href ? new URL(href, pageUrl).toString() : null;
}

async function fetchText(url: string, options: { allowMissing?: boolean } = {}): Promise<string> {
  const response = await fetch(url);
  if (response.status === 404 && options.allowMissing) return "";
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.text();
}

function sourceDetail(html: string): { title: string } {
  const detailHtml = html.match(/<p class="details">([\s\S]*?)<\/p>/)?.[1] ?? "";
  const title =
    detailHtml.match(/From\s+<a\b[^>]*>([\s\S]*?)<\/a>/)?.[1] ??
    detailHtml.match(/From\s+([^<]+)/)?.[1] ??
    "";
  return { title: cleanHtml(title) };
}

function splitTermExpansion(termText: string): { expansion: string; term: string } {
  const match = termText.match(/^([A-Za-z][A-Za-z0-9.+-]*)\s+\(([^)]+)\)$/);
  if (!match) return { expansion: termText, term: termText };
  return { expansion: cleanHtml(match[2] ?? termText), term: cleanHtml(match[1] ?? termText) };
}

function cleanHtml(input: string): string {
  return decodeHtmlEntities(
    input
      .replace(/<br\s*\/?>/gi, " ")
      .replace(/<\/(?:p|li|div|ol|ul)>/gi, " ")
      .replace(/<[^>]+>/g, " ")
  )
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:])/g, "$1")
    .trim();
}

function decodeHtmlEntities(input: string): string {
  return input.replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (entity, code: string) => {
    if (code.startsWith("#x")) return String.fromCodePoint(Number.parseInt(code.slice(2), 16));
    if (code.startsWith("#")) return String.fromCodePoint(Number.parseInt(code.slice(1), 10));
    return (
      {
        amp: "&",
        apos: "'",
        gt: ">",
        lt: "<",
        nbsp: " ",
        quot: '"'
      }[code.toLowerCase()] ?? entity
    );
  });
}
