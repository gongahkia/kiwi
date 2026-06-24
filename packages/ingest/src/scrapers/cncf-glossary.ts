import type { RawEntry, ScraperPlugin } from "../scraper.js";

type GitTreeResponse = {
  tree?: Array<{ path?: string; type?: string }>;
};

const sourceName = "cncf-glossary";
const treeUrl = "https://api.github.com/repos/cncf/glossary/git/trees/main?recursive=1";
const rawBaseUrl = "https://raw.githubusercontent.com/cncf/glossary/main";
const blobBaseUrl = "https://github.com/cncf/glossary/blob/main";
const publishedBaseUrl = "https://glossary.cncf.io";

export const cncfGlossaryScraper: ScraperPlugin = {
  name: sourceName,
  license: "CC-BY-4.0",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const paths = await fetchGlossaryPaths();
    const files = await fetchMarkdownFiles(paths);

    for (const { markdown, path } of files) {
      const entry = markdownToRawEntry(path, markdown, retrievedAt);
      if (entry) yield entry;
    }
  }
};

export async function fetchGlossaryPaths(): Promise<string[]> {
  const response = await fetch(treeUrl, {
    headers: { "user-agent": "wat-ingest/0.0 (https://github.com/wat/wat)" }
  });
  if (!response.ok) {
    throw new Error(`failed to fetch ${treeUrl}: ${response.status}`);
  }

  const data = (await response.json()) as GitTreeResponse;
  return (data.tree ?? [])
    .flatMap((item) => (item.type === "blob" && item.path ? [item.path] : []))
    .filter((path) => /^content\/[^/]+\/(?!_)[^/]+\.md$/.test(path))
    .filter((path) => !path.endsWith("/search.md"))
    .sort((left, right) => left.localeCompare(right));
}

export function markdownToRawEntry(
  path: string,
  markdown: string,
  retrievedAt: string
): RawEntry | null {
  const title = readFrontMatterValue(markdown, "title");
  const { expansion, term } = termFromTitle(path, title);
  const meaning = firstBodySection(markdown);
  if (!term || !meaning) return null;

  const lang = path.split("/")[1] ?? "unknown";
  const category = cleanText(readFrontMatterValue(markdown, "category")).toLowerCase();
  const tags = readTags(markdown).map((tag) => tag.toLowerCase());
  const domains = uniqueStrings(
    ["cncf", "cloud native", `lang:${lang}`, category, ...tags].filter(Boolean)
  );
  const aliases = aliasesForEntry(path, title, meaning);

  return {
    aliases,
    domains,
    expansion,
    meaning,
    sources: [
      {
        license: "CC-BY-4.0",
        publisher: "CNCF Cloud Native Glossary",
        retrieved_at: retrievedAt,
        snippet: meaning,
        source_quality: "canonical",
        title: `CNCF Cloud Native Glossary: ${term}`,
        url: `${blobBaseUrl}/${path}`
      },
      {
        license: "CC-BY-4.0",
        publisher: "CNCF Cloud Native Glossary",
        retrieved_at: retrievedAt,
        snippet: meaning,
        source_quality: "canonical",
        title: `CNCF Cloud Native Glossary: ${term}`,
        url: publishedUrl(path)
      }
    ],
    term
  };
}

async function fetchMarkdownFiles(
  paths: string[]
): Promise<Array<{ markdown: string; path: string }>> {
  const results: Array<{ markdown: string; path: string }> = [];
  for (let index = 0; index < paths.length; index += 16) {
    const batch = paths.slice(index, index + 16);
    results.push(
      ...(await Promise.all(
        batch.map(async (path) => ({
          markdown: await fetchText(`${rawBaseUrl}/${path}`),
          path
        }))
      ))
    );
  }
  return results;
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

function termFromTitle(path: string, title: string): { expansion: string; term: string } {
  const cleanTitle = cleanText(title);
  if (path === "content/en/cloud-native-tech.md" && cleanTitle === "Cloud Native Technology") {
    return { expansion: cleanTitle, term: "Cloud Native" };
  }

  const match = cleanTitle.match(/^(.+?)\s*\(([^()]+)\)$/);
  if (!match) return { expansion: cleanTitle, term: cleanTitle };
  return {
    expansion: cleanText(match[1] ?? cleanTitle),
    term: cleanText(match[2] ?? cleanTitle)
  };
}

function aliasesForEntry(path: string, title: string, meaning: string): string[] {
  if (path !== "content/en/cloud-native-tech.md") return [];

  const aliases = [cleanText(title)];
  if (/\bcloud native stack\b/i.test(meaning)) {
    aliases.push("Cloud Native Stack");
  }
  return uniqueStrings(aliases.filter(Boolean));
}

function firstBodySection(markdown: string): string {
  const body = markdown.replace(/^---\n[\s\S]*?\n---/, "").split(/\n##\s+/)[0] ?? "";
  return cleanText(body);
}

function readFrontMatterValue(markdown: string, key: string): string {
  const [, frontMatter = ""] = markdown.match(/^---\n([\s\S]*?)\n---/) ?? [];
  const line = frontMatter.split("\n").find((item) => item.startsWith(`${key}:`));
  if (!line) return "";
  return unquote(line.slice(key.length + 1).trim());
}

function readTags(markdown: string): string[] {
  const rawTags = readFrontMatterValue(markdown, "tags");
  const [, tags = ""] = rawTags.match(/^\[(.*)\]$/) ?? [];
  return tags
    .split(",")
    .map((tag) => cleanText(unquote(tag.trim())))
    .filter(Boolean);
}

function publishedUrl(path: string): string {
  const [, lang = "en", file = ""] = path.match(/^content\/([^/]+)\/([^/]+)\.md$/) ?? [];
  const slug = file.replace(/_/g, "-");
  return lang === "en" ? `${publishedBaseUrl}/${slug}/` : `${publishedBaseUrl}/${lang}/${slug}/`;
}

function cleanText(input: string): string {
  return input
    .replace(/\{\{<[^>]+>\}\}/g, " ")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values));
}

function unquote(value: string): string {
  return value.replace(/^["']|["']$/g, "");
}
