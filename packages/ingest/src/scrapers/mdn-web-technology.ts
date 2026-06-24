import type { RawEntry, ScraperPlugin } from "../scraper.js";

const sourceName = "mdn-web-technology";
const rawBaseUrl = "https://raw.githubusercontent.com/mdn/content/main";
const docsBaseUrl = "https://developer.mozilla.org/en-US/docs";
const indexPath = "files/en-us/web/index.md";
const supplementalConceptPaths = [
  "files/en-us/glossary/rest/index.md",
  "files/en-us/web/api/service_worker_api/index.md",
  "files/en-us/web/api/websockets_api/index.md"
];

export const mdnWebTechnologyScraper: ScraperPlugin = {
  name: sourceName,
  license: "CC-BY-SA-2.5",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const indexMarkdown = await fetchText(`${rawBaseUrl}/${indexPath}`);

    for (const entry of webIndexToRawEntries(indexMarkdown, retrievedAt)) {
      yield entry;
    }

    for (const path of supplementalConceptPaths) {
      const entry = markdownToRawEntry(path, await fetchText(`${rawBaseUrl}/${path}`), retrievedAt);
      if (entry) yield entry;
    }
  }
};

export function webIndexToRawEntries(markdown: string, retrievedAt: string): RawEntry[] {
  return webTechnologyReferenceSection(markdown).flatMap((line): RawEntry[] => {
    const match = line.match(/^- \[([^\]]+)\]\(\/en-US\/docs\/([^)]+)\)\s*-\s*:\s*(.+)$/);
    if (!match) return [];

    const label = cleanMarkdown(match[1] ?? "");
    const slug = match[2] ?? "";
    const meaning = cleanMarkdown(match[3] ?? "");
    const term = termFromLabel(label);
    if (!term || !meaning) return [];

    return [
      {
        aliases: aliasesFromLabel(label, term),
        domains: domainsForSlug(slug),
        expansion: label,
        meaning,
        sources: [
          {
            license: "CC-BY-SA-2.5",
            publisher: "Mozilla Contributors",
            retrieved_at: retrievedAt,
            snippet: meaning,
            source_quality: "canonical",
            title: `MDN Web technology for developers: ${term}`,
            url: `${docsBaseUrl}/${slug}`
          }
        ],
        term
      }
    ];
  });
}

export function markdownToRawEntry(
  path: string,
  markdown: string,
  retrievedAt: string
): RawEntry | null {
  const frontMatter = parseFrontMatter(markdown);
  const body = markdown.replace(/^---[\s\S]*?---/, "").replace(/\{\{[^}]+\}\}/g, macroText);
  const meaning = firstParagraph(body);
  if (!frontMatter.title || !frontMatter.slug || !meaning) return null;

  const { aliases, expansion, term } = conceptNames(path, frontMatter.title, meaning);
  return {
    aliases,
    domains: domainsForSlug(frontMatter.slug),
    expansion,
    meaning,
    sources: [
      {
        license: "CC-BY-SA-2.5",
        publisher: "Mozilla Contributors",
        retrieved_at: retrievedAt,
        snippet: meaning,
        source_quality: "canonical",
        title: `MDN Web technology: ${term}`,
        url: `${docsBaseUrl}/${frontMatter.slug}`
      }
    ],
    term
  };
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

function webTechnologyReferenceSection(markdown: string): string[] {
  const section = markdown.split("\n## Web technology references\n")[1]?.split(/\n##\s+/)[0] ?? "";
  return section
    .replace(/\n\s+-\s+:\s+/g, " - : ")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

function parseFrontMatter(markdown: string): { slug: string; title: string } {
  const [, frontMatter = ""] = markdown.match(/^---\n([\s\S]*?)\n---/) ?? [];
  return {
    slug: unquote(frontMatter.match(/^slug:\s*(.+)$/m)?.[1]?.trim() ?? ""),
    title: unquote(frontMatter.match(/^title:\s*(.+)$/m)?.[1]?.trim() ?? "")
  };
}

function conceptNames(
  path: string,
  title: string,
  meaning: string
): { aliases: string[]; expansion: string; term: string } {
  if (path === "files/en-us/glossary/rest/index.md") {
    return {
      aliases: ["Representational State Transfer"],
      expansion: expansionFromBody(title, meaning) ?? title,
      term: "REST"
    };
  }
  if (path === "files/en-us/web/api/service_worker_api/index.md") {
    return {
      aliases: [title, "Service workers"],
      expansion: title,
      term: "Service Worker"
    };
  }
  if (path === "files/en-us/web/api/websockets_api/index.md") {
    return {
      aliases: [title, "WebSockets"],
      expansion: "WebSocket API",
      term: "WebSocket"
    };
  }

  return {
    aliases: aliasesFromLabel(title, termFromLabel(title)),
    expansion: title,
    term: termFromLabel(title)
  };
}

function firstParagraph(markdown: string): string {
  const paragraphs = markdown
    .split(/\n\s*\n/)
    .map(cleanMarkdown)
    .filter(
      (paragraph) =>
        paragraph.length >= 40 && !paragraph.startsWith(">") && !paragraph.startsWith("##")
    );
  return paragraphs[0] ?? "";
}

function expansionFromBody(title: string, meaning: string): string | null {
  if (!/^[A-Z0-9][A-Z0-9+.-]+$/.test(title)) return null;
  const match = meaning.match(new RegExp(`^${escapeRegExp(title)} \\(([^)]+)\\)`));
  return match?.[1] ?? null;
}

function termFromLabel(label: string): string {
  return cleanMarkdown(label).replace(/\s*\(([^)]+)\)\s*$/, "");
}

function aliasesFromLabel(label: string, term: string): string[] {
  const aliases = [];
  const parenthetical = label.match(/\(([^)]+)\)\s*$/)?.[1];
  if (parenthetical) aliases.push(parenthetical);
  if (label !== term) aliases.push(label);
  return uniqueStrings(aliases.map(cleanMarkdown).filter(Boolean));
}

function domainsForSlug(slug: string): string[] {
  const domains = ["web platform", "mdn", "web technology"];
  if (/^Web\/API\b/.test(slug)) domains.push("web api");
  if (/^Web\/HTTP\b/.test(slug) || slug === "Glossary/REST") domains.push("http");
  if (/^Web\/CSS\b/.test(slug)) domains.push("css");
  if (/^Web\/HTML\b/.test(slug)) domains.push("html");
  if (/^Web\/JavaScript\b/.test(slug)) domains.push("javascript");
  if (/Progressive_web_apps/.test(slug)) domains.push("pwa");
  return domains;
}

function cleanMarkdown(input: string): string {
  return input
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[*_`]/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function macroText(input: string): string {
  const quotedArgs = Array.from(input.matchAll(/"([^"]+)"/g), (match) => match[1] ?? "");
  return quotedArgs.at(1) ?? quotedArgs[0] ?? " ";
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values));
}

function unquote(value: string): string {
  return value.replace(/^["']|["']$/g, "");
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
