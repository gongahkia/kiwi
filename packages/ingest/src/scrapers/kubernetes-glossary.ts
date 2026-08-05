import type { RawEntry, ScraperPlugin } from "../scraper.js";

const sourceName = "kubernetes-glossary";
const glossaryTreeUrl =
  "https://github.com/kubernetes/website/tree/main/content/en/docs/reference/glossary";
const rawBaseUrl =
  "https://raw.githubusercontent.com/kubernetes/website/main/content/en/docs/reference/glossary";
const docsBaseUrl = "https://kubernetes.io/docs/reference/glossary/";

export const kubernetesGlossaryScraper: ScraperPlugin = {
  name: sourceName,
  license: "CC-BY-4.0",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const files = await fetchGlossaryFiles();
    const markdownFiles = await Promise.all(
      files.map(async (file) => ({
        file,
        markdown: await fetchText(`${rawBaseUrl}/${file}`)
      }))
    );

    for (const { file, markdown } of markdownFiles) {
      const entry = markdownToRawEntry(file, markdown, retrievedAt);
      if (entry) yield entry;
    }
  }
};

export async function fetchGlossaryFiles(): Promise<string[]> {
  const html = await fetchText(glossaryTreeUrl);
  const matches = html.matchAll(
    /\/kubernetes\/website\/blob\/main\/content\/en\/docs\/reference\/glossary\/([^"?]+\.md)/g
  );
  return Array.from(new Set(Array.from(matches, (match) => match[1] ?? "")))
    .filter((file) => file !== "index.md")
    .sort((left, right) => left.localeCompare(right));
}

export function markdownToRawEntry(
  file: string,
  markdown: string,
  retrievedAt: string
): RawEntry | null {
  const frontMatter = parseFrontMatter(markdown);
  const id = frontMatter.id || file.replace(/\.md$/, "");
  const title = frontMatter.title || titleFromFile(file);
  const body = markdown.replace(/^---[\s\S]*?---/, "").split("<!--more-->")[0] ?? "";
  const meaning = cleanText(frontMatter.short_description || body);
  if (!title || !meaning) return null;

  return {
    domains: ["kubernetes", ...frontMatter.tags],
    expansion: expansionFromBody(title, body) ?? title,
    meaning,
    sources: [
      {
        license: "CC-BY-4.0",
        publisher: "Kubernetes Documentation",
        retrieved_at: retrievedAt,
        snippet: meaning,
        source_quality: "canonical",
        title: `Kubernetes glossary: ${title}`,
        url: `${docsBaseUrl}?all=true#term-${id}`
      }
    ],
    term: title
  };
}

async function fetchText(url: string): Promise<string> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.text();
}

function parseFrontMatter(markdown: string): {
  id: string;
  short_description: string;
  tags: string[];
  title: string;
} {
  const [, frontMatter = ""] = markdown.match(/^---\n([\s\S]*?)\n---/) ?? [];
  const lines = frontMatter.split("\n");
  const result = {
    id: "",
    short_description: "",
    tags: [] as string[],
    title: ""
  };

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index] ?? "";
    if (line.startsWith("title:")) {
      result.title = unquote(line.slice("title:".length).trim());
    } else if (line.startsWith("id:")) {
      result.id = unquote(line.slice("id:".length).trim());
    } else if (line.startsWith("short_description:")) {
      result.short_description = readFoldedValue(lines, index);
    } else if (line.startsWith("tags:")) {
      result.tags = readList(lines, index);
    }
  }

  return result;
}

function readFoldedValue(lines: string[], startIndex: number): string {
  const firstLine = lines[startIndex] ?? "";
  const inlineValue = firstLine.replace(/^short_description:\s*>?\s*/, "").trim();
  if (inlineValue) return cleanText(inlineValue);

  const values = [];
  for (let index = startIndex + 1; index < lines.length; index += 1) {
    const line = lines[index] ?? "";
    if (/^\w/.test(line)) break;
    if (line.trim()) values.push(line.trim());
  }
  return cleanText(values.join(" "));
}

function readList(lines: string[], startIndex: number): string[] {
  const values = [];
  for (let index = startIndex + 1; index < lines.length; index += 1) {
    const line = lines[index] ?? "";
    if (!line.startsWith("- ")) break;
    values.push(cleanText(line.slice(2)));
  }
  return values;
}

function expansionFromBody(title: string, body: string): string | null {
  const escapedTitle = title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = cleanText(body).match(new RegExp(`^${escapedTitle} \\(([^)]+)\\)`));
  return match?.[1] ?? null;
}

function titleFromFile(file: string): string {
  return file
    .replace(/\.md$/, "")
    .split("-")
    .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1))
    .join(" ");
}

function unquote(value: string): string {
  return value.replace(/^["']|["']$/g, "");
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
