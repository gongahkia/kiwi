import type { RawEntry, RawSourceCitation, ScraperPlugin } from "../scraper.js";

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

type PageSpec = {
  kind: "glossary" | "outline";
  title: string;
};

const sourceName = "wikipedia-outline";
const apiUrl = "https://en.wikipedia.org/w/api.php";
const pages: PageSpec[] = [
  { kind: "outline", title: "Outline of computer science" },
  { kind: "glossary", title: "Glossary of computer science" },
  { kind: "outline", title: "Outline of computing" }
];

const stopHeadings = new Set([
  "see also",
  "references",
  "external links",
  "further reading",
  "notes"
]);

export const wikipediaOutlineScraper: ScraperPlugin = {
  name: sourceName,
  license: "CC-BY-SA-4.0",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();

    for (const spec of pages) {
      const page = await fetchPage(spec.title);
      const content = page.revisions?.[0]?.slots?.main?.content ?? "";
      const pageTitle = page.title ?? spec.title;
      const pageUrl = page.fullurl ?? wikipediaUrl(spec.title);
      for (const entry of wikitextToRawEntries(
        pageTitle,
        spec.kind,
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
  kind: PageSpec["kind"],
  wikitext: string,
  pageUrl: string,
  retrievedAt: string
): RawEntry[] {
  const pageEntries =
    kind === "glossary"
      ? glossaryWikitextToRawEntries(pageTitle, wikitext, pageUrl, retrievedAt)
      : outlineWikitextToRawEntries(pageTitle, wikitext, pageUrl, retrievedAt);

  return dedupeRawEntries([
    ...pageEntries,
    ...linkedConceptsToRawEntries(pageTitle, wikitext, pageUrl, retrievedAt)
  ]);
}

export function glossaryWikitextToRawEntries(
  pageTitle: string,
  wikitext: string,
  pageUrl: string,
  retrievedAt: string
): RawEntry[] {
  const entries: RawEntry[] = [];
  let current: { aliases: string[]; term: string } | null = null;

  for (const line of articleWikitext(wikitext).split("\n")) {
    const termBody = templateLineBody(line, "term");
    if (termBody !== null) {
      current = parseGlossaryTerm(termBody);
      continue;
    }

    const definitionBody = templateLineBody(line, "defn");
    if (!current || definitionBody === null) continue;

    const definition = cleanMeaning(templateContent(definitionBody));
    if (!isValidMeaning(definition)) continue;

    entries.push(
      rawEntry({
        aliases: current.aliases,
        domains: domainsFor(pageTitle, "glossary"),
        meaning: definition,
        pageTitle,
        pageUrl,
        retrievedAt,
        term: current.term
      })
    );
    current = null;
  }

  return dedupeRawEntries(entries);
}

export function outlineWikitextToRawEntries(
  pageTitle: string,
  wikitext: string,
  pageUrl: string,
  retrievedAt: string
): RawEntry[] {
  const entries: RawEntry[] = [];
  let section = "";

  for (const line of articleWikitext(wikitext).split("\n")) {
    const heading = parseHeading(line);
    if (heading) {
      section = heading;
      continue;
    }

    const match = line.match(/^(\*+)\s*(.+)$/);
    if (!match) continue;

    const content = match[2] ?? "";
    const term = extractLeadingConcept(content);
    if (!term || !isValidTerm(term)) continue;

    const description = cleanMeaning(descriptionFromListItem(content));
    const meaning = isValidMeaning(description)
      ? description
      : `${term} is listed in Wikipedia's ${pageTitle}.`;

    entries.push(
      rawEntry({
        domains: domainsFor(pageTitle, "outline", section),
        meaning,
        pageTitle,
        pageUrl,
        retrievedAt,
        term
      })
    );
  }

  return dedupeRawEntries(entries);
}

export function linkedConceptsToRawEntries(
  pageTitle: string,
  wikitext: string,
  pageUrl: string,
  retrievedAt: string
): RawEntry[] {
  const entries: RawEntry[] = [];
  const body = articleWikitext(wikitext);
  const matches = body.matchAll(/\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]/g);

  for (const match of matches) {
    const target = cleanWikitext(match[1] ?? "");
    if (!isArticleLinkTarget(target)) continue;

    const label = cleanWikitext(match[2] ?? target);
    const term = cleanTerm(label || target);
    if (!isValidTerm(term) || isMetaConcept(term)) continue;

    entries.push(
      rawEntry({
        domains: domainsFor(pageTitle, "linked concept"),
        meaning: `${term} is a computing concept linked from Wikipedia's ${pageTitle}.`,
        pageTitle,
        pageUrl,
        retrievedAt,
        term
      })
    );
  }

  return dedupeRawEntries(entries);
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

function rawEntry(input: {
  aliases?: string[];
  domains: string[];
  meaning: string;
  pageTitle: string;
  pageUrl: string;
  retrievedAt: string;
  term: string;
}): RawEntry {
  return {
    aliases: input.aliases,
    domains: input.domains,
    expansion: input.term,
    meaning: input.meaning,
    sources: [
      {
        license: "CC-BY-SA-4.0",
        publisher: "Wikipedia contributors",
        retrieved_at: input.retrievedAt,
        snippet: input.meaning,
        source_quality: "secondary",
        title: `Wikipedia ${input.pageTitle}: ${input.term}`,
        url: input.pageUrl
      }
    ],
    term: input.term
  };
}

function parseGlossaryTerm(body: string): { aliases: string[]; term: string } | null {
  const text = cleanWikitext(templateContent(body));
  const aliases = parentheticalAliases(text);
  const term = cleanTerm(text.replace(/\s+\([^)]{1,80}\)\s*$/g, ""));
  if (!isValidTerm(term)) return null;
  return { aliases, term };
}

function templateLineBody(line: string, name: string): string | null {
  const trimmed = line.trim();
  const prefix = `{{${name}|`;
  if (!trimmed.startsWith(prefix) || !trimmed.endsWith("}}")) return null;
  return trimmed.slice(prefix.length, -2);
}

function templateContent(input: string): string {
  return splitTemplateArgs(input)
    .flatMap((part) => {
      const match = part.match(/^\s*([a-zA-Z0-9_-]+)\s*=\s*([\s\S]*)$/);
      if (!match) return [part];
      return /^\d+$/.test(match[1] ?? "") ? [match[2] ?? ""] : [];
    })
    .join(" ");
}

function splitTemplateArgs(input: string): string[] {
  const parts: string[] = [];
  let current = "";
  let braceDepth = 0;
  let linkDepth = 0;

  for (let i = 0; i < input.length; i += 1) {
    const two = input.slice(i, i + 2);
    if (two === "{{") {
      braceDepth += 1;
      current += two;
      i += 1;
      continue;
    }
    if (two === "}}" && braceDepth > 0) {
      braceDepth -= 1;
      current += two;
      i += 1;
      continue;
    }
    if (two === "[[") {
      linkDepth += 1;
      current += two;
      i += 1;
      continue;
    }
    if (two === "]]" && linkDepth > 0) {
      linkDepth -= 1;
      current += two;
      i += 1;
      continue;
    }
    if (input[i] === "|" && braceDepth === 0 && linkDepth === 0) {
      parts.push(current.trim());
      current = "";
      continue;
    }
    current += input[i] ?? "";
  }

  parts.push(current.trim());
  return parts;
}

function articleWikitext(wikitext: string): string {
  const lines: string[] = [];
  for (const line of wikitext.split("\n")) {
    const heading = parseHeading(line);
    if (heading && stopHeadings.has(heading.toLowerCase())) break;
    lines.push(line);
  }
  return lines.join("\n");
}

function parseHeading(line: string): string {
  const match = line.match(/^={2,6}\s*(.+?)\s*={2,6}$/);
  return match ? cleanWikitext(match[1] ?? "") : "";
}

function extractLeadingConcept(content: string): string {
  const linkMatch = content.match(/\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]/);
  if (linkMatch && isArticleLinkTarget(linkMatch[1] ?? "")) {
    return cleanTerm(cleanWikitext(linkMatch[2] ?? linkMatch[1] ?? ""));
  }

  return cleanTerm(
    cleanWikitext(content.split(/\s+(?:&ndash;|&mdash;|-|\u2013|\u2014)\s+/)[0] ?? "")
  );
}

function descriptionFromListItem(content: string): string {
  return content
    .split(/\s+(?:&ndash;|&mdash;|-|\u2013|\u2014)\s+/)
    .slice(1)
    .join(" - ");
}

function domainsFor(
  pageTitle: string,
  kind: "glossary" | "linked concept" | "outline",
  section = ""
): string[] {
  return uniqueStrings([
    "wikipedia",
    "computer science",
    "computing",
    kind,
    pageTitle.toLowerCase(),
    section.toLowerCase()
  ]);
}

function cleanTerm(input: string): string {
  return input
    .replace(/\s+or\s+.+$/i, "")
    .replace(
      /\s+\((?:computer science|computing|software|software engineering|programming)\)$/i,
      ""
    )
    .replace(/\s+\(disambiguation\)$/i, "")
    .replace(/^the\s+/i, "")
    .trim();
}

function cleanMeaning(input: string): string {
  return cleanWikitext(input)
    .replace(/^\d+\s*[-.)]\s*/, "")
    .replace(/\s+/g, " ")
    .trim();
}

function cleanWikitext(input: string): string {
  return decodeHtmlEntities(
    stripTemplates(
      input
        .replace(/<!--[\s\S]*?-->/g, " ")
        .replace(/<ref[\s\S]*?<\/ref>/gi, " ")
        .replace(/<ref[^>]*\/>/gi, " ")
        .replace(/\{\{(?:gli|glossary link)\|([^{}|]+)\|([^{}]+)\}\}/gi, "$2")
        .replace(/\{\{(?:gli|glossary link)\|([^{}|]+)\}\}/gi, "$1")
        .replace(/\{\{(?:abbr|code|kbd|lang|math|mono|nowrap|samp|var)\|([^{}|]+)\}\}/gi, "$1")
        .replace(/\[\[([^|\]]+)\|([^\]]+)\]\]/g, "$2")
        .replace(/\[\[([^\]]+)\]\]/g, "$1")
        .replace(/\[https?:\/\/[^\s\]]+\s+([^\]]+)\]/g, "$1")
        .replace(/\[https?:\/\/[^\s\]]+\]/g, " ")
        .replace(/''+/g, "")
        .replace(/<sup>([\s\S]*?)<\/sup>/gi, "$1")
        .replace(/<[^>]+>/g, " ")
    )
  )
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:])/g, "$1")
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")")
    .trim();
}

function stripTemplates(input: string): string {
  let output = input;
  for (let i = 0; i < 8; i += 1) {
    const next = output.replace(/\{\{[^{}]*\}\}/g, " ");
    if (next === output) return output;
    output = next;
  }
  return output;
}

function parentheticalAliases(input: string): string[] {
  const aliases = Array.from(input.matchAll(/\(([^)]+)\)/g))
    .flatMap((match) => (match[1] ?? "").split(/\s*(?:,|;|\/|\bor\b)\s*/i))
    .map((alias) => alias.trim())
    .filter((alias) => alias.length >= 2 && alias.length <= 40 && /^[A-Za-z0-9.+#-]+$/.test(alias));
  return uniqueStrings(aliases);
}

function isArticleLinkTarget(target: string): boolean {
  const clean = target.trim();
  if (!clean || clean.startsWith("#")) return false;
  return !/^(?:category|file|help|image|portal|special|talk|template|wikipedia):/i.test(clean);
}

function isMetaConcept(term: string): boolean {
  return /^(?:glossary|index|list of|outline of|timeline of)\b/i.test(term);
}

function isValidTerm(term: string): boolean {
  return (
    term.length >= 2 &&
    term.length <= 90 &&
    /[\p{Letter}\p{Number}]/u.test(term) &&
    !/[{}[\]|<>]/.test(term) &&
    !/^https?:/i.test(term)
  );
}

function isValidMeaning(meaning: string): boolean {
  return meaning.length >= 8 && meaning.length <= 700 && /[\p{Letter}\p{Number}]/u.test(meaning);
}

function dedupeRawEntries(entries: RawEntry[]): RawEntry[] {
  const deduped = new Map<string, RawEntry>();

  for (const entry of entries) {
    const key = `${normalize(entry.term)}:${normalize(entry.expansion ?? entry.term)}`;
    const existing = deduped.get(key);
    deduped.set(key, existing ? mergeRawEntries(existing, entry) : entry);
  }

  return Array.from(deduped.values());
}

function mergeRawEntries(left: RawEntry, right: RawEntry): RawEntry {
  return {
    ...left,
    aliases: uniqueStrings([...(left.aliases ?? []), ...(right.aliases ?? [])]),
    domains: uniqueStrings([...(left.domains ?? []), ...(right.domains ?? [])]),
    examples: uniqueStrings([...(left.examples ?? []), ...(right.examples ?? [])]),
    sources: mergeSources(left.sources, right.sources)
  };
}

function mergeSources(left: RawSourceCitation[], right: RawSourceCitation[]): RawSourceCitation[] {
  const sources = new Map<string, RawSourceCitation>();
  for (const source of [...left, ...right]) sources.set(source.url, source);
  return Array.from(sources.values());
}

function normalize(input: string): string {
  return input
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function uniqueStrings(values: Array<string | undefined>): string[] {
  return Array.from(
    new Set(values.map((value) => value?.trim()).filter((value): value is string => Boolean(value)))
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
        mdash: "-",
        nbsp: " ",
        ndash: "-",
        quot: '"'
      }[code.toLowerCase()] ?? entity
    );
  });
}
