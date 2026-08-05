import type { RawEntry, ScraperPlugin } from "../scraper.js";

interface GithubGlossaryOptions {
  domains?: string[];
  license: string;
  publisher: string;
  retrievedAt: string;
  sourceUrl: string;
}

export function parseGithubGlossaryMarkdown(
  markdown: string,
  options: GithubGlossaryOptions
): RawEntry[] {
  return [...parseTableRows(markdown, options), ...parseHeadingRows(markdown, options)];
}

function parseTableRows(markdown: string, options: GithubGlossaryOptions): RawEntry[] {
  const lines = markdown.split(/\r?\n/u);
  const entries: RawEntry[] = [];
  for (let index = 0; index < lines.length - 1; index += 1) {
    const header = tableCells(lines[index] ?? "");
    const divider = tableCells(lines[index + 1] ?? "");
    if (!isGlossaryHeader(header) || !divider.every((cell) => /^:?-{3,}:?$/u.test(cell))) continue;
    for (let rowIndex = index + 2; rowIndex < lines.length; rowIndex += 1) {
      const cells = tableCells(lines[rowIndex] ?? "");
      if (cells.length < 2) break;
      const entry = entryFromCells(header, cells, options);
      if (entry) entries.push(entry);
    }
  }
  return entries;
}

function parseHeadingRows(markdown: string, options: GithubGlossaryOptions): RawEntry[] {
  return markdown.split(/\r?\n/u).flatMap((line) => {
    const match = line.match(/^#{2,4}\s+([A-Za-z][A-Za-z0-9.+#-]{1,30})\s*(?:-|–|—|:)\s+(.+)$/u);
    if (!match?.[1] || !match[2]) return [];
    return [
      rawEntry({
        domains: options.domains,
        expansion: stripMarkdown(match[2]),
        meaning: stripMarkdown(match[2]),
        options,
        term: match[1]
      })
    ];
  });
}

function tableCells(line: string): string[] {
  const trimmed = line.trim();
  if (!trimmed.startsWith("|") || !trimmed.endsWith("|")) return [];
  return trimmed
    .slice(1, -1)
    .split("|")
    .map((cell) => stripMarkdown(cell));
}

function isGlossaryHeader(cells: string[]): boolean {
  const normalized = cells.map((cell) => cell.toLowerCase());
  return (
    normalized.includes("term") &&
    normalized.some((cell) => cell === "expansion" || cell === "definition" || cell === "meaning")
  );
}

function entryFromCells(
  header: string[],
  cells: string[],
  options: GithubGlossaryOptions
): RawEntry | null {
  const value = (name: string): string => {
    const index = header.findIndex((cell) => cell.toLowerCase() === name);
    return index >= 0 ? (cells[index] ?? "") : "";
  };
  const term = value("term");
  const expansion = value("expansion") || value("definition") || value("meaning");
  if (!term || !expansion) return null;
  const meaning = value("meaning") || value("definition") || expansion;
  const domains = csv(value("domains") || value("domain"));
  const aliases = csv(value("aliases") || value("alias"));
  const contemporaries = csv(value("contemporaries") || value("alternatives"));
  return rawEntry({
    aliases,
    contemporaries,
    domains: domains.length ? domains : options.domains,
    expansion,
    meaning,
    options,
    term
  });
}

function rawEntry(input: {
  aliases?: string[];
  contemporaries?: string[];
  domains?: string[];
  expansion: string;
  meaning: string;
  options: GithubGlossaryOptions;
  term: string;
}): RawEntry {
  return {
    aliases: input.aliases,
    contemporaries: input.contemporaries,
    domains: input.domains,
    expansion: input.expansion,
    meaning: input.meaning,
    sources: [
      {
        license: input.options.license,
        publisher: input.options.publisher,
        retrieved_at: input.options.retrievedAt,
        snippet: input.meaning,
        source_quality: "community",
        title: "GitHub glossary",
        url: input.options.sourceUrl
      }
    ],
    term: input.term
  };
}

function csv(value: string): string[] {
  return value
    .split(/[,;]/u)
    .map((item) => item.trim())
    .filter(Boolean);
}

function stripMarkdown(value: string): string {
  return value
    .replace(/`([^`]+)`/gu, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/gu, "$1")
    .replace(/\s+/gu, " ")
    .trim();
}

export const githubGlossaryScraper: ScraperPlugin = {
  name: "github-glossary",
  license: process.env.GITHUB_GLOSSARY_LICENSE ?? "MIT",
  refresh_interval: "manual",
  async *fetch() {
    const sourceUrl = process.env.GITHUB_GLOSSARY_URL?.trim();
    if (!sourceUrl) throw new Error("GITHUB_GLOSSARY_URL is required");
    const response = await fetch(sourceUrl);
    if (!response.ok) throw new Error(`GITHUB_GLOSSARY_URL returned ${response.status}`);
    const markdown = await response.text();
    yield* parseGithubGlossaryMarkdown(markdown, {
      domains: csv(process.env.GITHUB_GLOSSARY_DOMAINS ?? ""),
      license: process.env.GITHUB_GLOSSARY_LICENSE ?? "MIT",
      publisher: process.env.GITHUB_GLOSSARY_PUBLISHER ?? "GitHub glossary",
      retrievedAt: new Date().toISOString(),
      sourceUrl
    });
  }
};
