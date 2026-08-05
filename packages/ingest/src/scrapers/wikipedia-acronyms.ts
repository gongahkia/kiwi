import type { RawEntry, ScraperPlugin } from "../scraper.js";

type WikipediaPage = {
  fullurl?: string;
  revisions?: Array<{
    slots?: {
      main?: {
        content?: string;
      };
    };
  }>;
  title?: string;
};

type WikipediaQueryResponse = {
  query?: {
    pages?: WikipediaPage[];
  };
};

const sourceName = "wikipedia-acronyms";
const apiUrl = "https://en.wikipedia.org/w/api.php";
const pages = [
  "List of acronyms: 0\u20139",
  ..."ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("").map((letter) => `List of acronyms: ${letter}`)
];

export const wikipediaAcronymsScraper: ScraperPlugin = {
  name: sourceName,
  license: "CC-BY-SA-4.0",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();

    for (const title of pages) {
      const page = await fetchPage(title);
      const content = page.revisions?.[0]?.slots?.main?.content ?? "";
      const pageUrl = page.fullurl ?? wikipediaUrl(title);
      for (const entry of wikitextToRawEntries(
        page.title ?? title,
        content,
        pageUrl,
        retrievedAt
      )) {
        yield entry;
      }
    }
  }
};

export function wikitextToRawEntries(
  pageTitle: string,
  wikitext: string,
  pageUrl: string,
  retrievedAt: string
): RawEntry[] {
  const entries: RawEntry[] = [];
  let currentTerm = "";

  for (const line of wikitext.split("\n")) {
    const match = line.match(/^(\*+)\s*(.+)$/);
    if (!match) continue;

    const depth = match[1]?.length ?? 0;
    const content = match[2] ?? "";
    if (depth === 1) {
      const parsed = parseTopLevelItem(content);
      if (!parsed) {
        currentTerm = "";
        continue;
      }

      currentTerm = parsed.term;
      if (parsed.expansion) {
        entries.push(rawEntry(parsed.term, parsed.expansion, pageTitle, pageUrl, retrievedAt));
      }
    } else if (currentTerm) {
      const expansion = cleanExpansion(content);
      if (isValidExpansion(expansion)) {
        entries.push(rawEntry(currentTerm, expansion, pageTitle, pageUrl, retrievedAt));
      }
    }
  }

  return entries;
}

async function fetchPage(title: string): Promise<WikipediaPage> {
  const url = new URL(apiUrl);
  url.searchParams.set("action", "query");
  url.searchParams.set("format", "json");
  url.searchParams.set("formatversion", "2");
  url.searchParams.set("inprop", "url");
  url.searchParams.set("prop", "info|revisions");
  url.searchParams.set("rvprop", "content");
  url.searchParams.set("rvslots", "main");
  url.searchParams.set("titles", title);

  const response = await fetch(url, {
    headers: { "user-agent": "wat-ingest/0.0 (https://github.com/wat/wat)" }
  });
  if (!response.ok) {
    throw new Error(`failed to fetch ${title}: ${response.status}`);
  }

  const data = (await response.json()) as WikipediaQueryResponse;
  const page = data.query?.pages?.[0];
  if (!page) throw new Error(`missing wikipedia page: ${title}`);
  return page;
}

function parseTopLevelItem(content: string): { expansion: string; term: string } | null {
  const parts = content.split(/\s+(?:\u2013|\u2014|-)\s+/);
  const term = cleanTerm(parts[0] ?? "");
  if (!isValidTerm(term)) return null;

  const expansion = parts.length > 1 ? cleanExpansion(parts.slice(1).join(" - ")) : "";
  return { expansion: isValidExpansion(expansion) ? expansion : "", term };
}

function rawEntry(
  term: string,
  expansion: string,
  pageTitle: string,
  pageUrl: string,
  retrievedAt: string
): RawEntry {
  return {
    domains: ["wikipedia", "acronyms"],
    expansion,
    meaning: expansion,
    sources: [
      {
        license: "CC-BY-SA-4.0",
        publisher: "Wikipedia contributors",
        retrieved_at: retrievedAt,
        snippet: expansion,
        source_quality: "community",
        title: `Wikipedia ${pageTitle}: ${term}`,
        url: pageUrl
      }
    ],
    term
  };
}

function cleanTerm(input: string): string {
  return cleanWikitext(input)
    .replace(/\s+or\s+.+$/i, "")
    .replace(/\s+\(disambiguation\)$/i, "")
    .trim();
}

function cleanExpansion(input: string): string {
  return cleanWikitext(input)
    .replace(/^\((?:a|i|p|s|a\/i|i\/a|i\/s)\)\s*/i, "")
    .replace(/^many,\s+including\s+/i, "")
    .replace(/\s*;\s*see entry$/i, "")
    .trim();
}

function cleanWikitext(input: string): string {
  return decodeHtmlEntities(
    input
      .replace(/<!--[\s\S]*?-->/g, " ")
      .replace(/<ref[\s\S]*?<\/ref>/gi, " ")
      .replace(/\{\{[^{}]*\}\}/g, " ")
      .replace(/\[\[([^|\]]+)\|([^\]]+)\]\]/g, "$2")
      .replace(/\[\[([^\]]+)\]\]/g, "$1")
      .replace(/\[https?:\/\/[^\s\]]+\s+([^\]]+)\]/g, "$1")
      .replace(/''+/g, "")
      .replace(/<sup>([\s\S]*?)<\/sup>/gi, "$1")
      .replace(/<[^>]+>/g, " ")
  )
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:])/g, "$1")
    .trim();
}

function isValidTerm(term: string): boolean {
  return term.length > 0 && term.length <= 40 && /[\p{Letter}\p{Number}]/u.test(term);
}

function isValidExpansion(expansion: string): boolean {
  return (
    expansion.length > 1 &&
    expansion.length <= 220 &&
    /[\p{Letter}\p{Number}]/u.test(expansion) &&
    !/^see\b/i.test(expansion)
  );
}

function wikipediaUrl(title: string): string {
  return `https://en.wikipedia.org/wiki/${encodeURIComponent(title.replaceAll(" ", "_"))}`;
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
