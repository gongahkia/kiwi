import { execFile as execFileCallback } from "node:child_process";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { promisify } from "node:util";

import type { RawEntry, ScraperPlugin } from "../scraper.js";

const execFile = promisify(execFileCallback);
const sourceName = "mdn-glossary";
const repoUrl = "https://github.com/mdn/content.git";
const glossaryPath = "files/en-us/glossary";

export const mdnGlossaryScraper: ScraperPlugin = {
  name: sourceName,
  license: "CC-BY-SA-2.5",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const dir = await mkdtemp(join(tmpdir(), "wat-mdn-content-"));

    try {
      await execFile("git", [
        "clone",
        "--depth",
        "1",
        "--filter=blob:none",
        "--sparse",
        repoUrl,
        dir
      ]);
      await execFile("git", ["-C", dir, "sparse-checkout", "set", glossaryPath]);

      for (const file of await glossaryFiles(join(dir, glossaryPath))) {
        const markdown = await readFile(file, "utf8");
        const entry = markdownToRawEntry(
          relative(join(dir, glossaryPath), file),
          markdown,
          retrievedAt
        );
        if (entry) yield entry;
      }
    } finally {
      await rm(dir, { force: true, recursive: true });
    }
  }
};

export function markdownToRawEntry(
  relativePath: string,
  markdown: string,
  retrievedAt: string
): RawEntry | null {
  const frontMatter = parseFrontMatter(markdown);
  const title = frontMatter.title || titleFromPath(relativePath);
  const slug = frontMatter.slug || `Glossary/${relativePath.split("/")[0] ?? title}`;
  const body = markdown.replace(/^---[\s\S]*?---/, "").replace(/\{\{[^}]+\}\}/g, macroText);
  const meaning = firstParagraph(body);
  if (!title || !meaning) return null;

  return {
    domains: ["web platform", "mdn"],
    expansion: expansionFromBody(title, meaning) ?? title,
    meaning,
    sources: [
      {
        license: "CC-BY-SA-2.5",
        publisher: "Mozilla Contributors",
        retrieved_at: retrievedAt,
        snippet: meaning,
        source_quality: "canonical",
        title: `MDN glossary: ${title}`,
        url: `https://developer.mozilla.org/en-US/docs/${slug}`
      }
    ],
    term: title
  };
}

async function glossaryFiles(root: string): Promise<string[]> {
  const files = [];
  for (const item of await readdir(root, { withFileTypes: true })) {
    const path = join(root, item.name);
    if (item.isDirectory()) {
      const indexPath = join(path, "index.md");
      files.push(indexPath);
    }
  }
  return files.sort((left, right) => left.localeCompare(right));
}

function parseFrontMatter(markdown: string): { slug: string; title: string } {
  const [, frontMatter = ""] = markdown.match(/^---\n([\s\S]*?)\n---/) ?? [];
  const title = frontMatter.match(/^title:\s*(.+)$/m)?.[1]?.trim() ?? "";
  const slug = frontMatter.match(/^slug:\s*(.+)$/m)?.[1]?.trim() ?? "";
  return {
    slug: unquote(slug),
    title: unquote(title)
  };
}

function firstParagraph(markdown: string): string {
  const paragraphs = markdown
    .split(/\n\s*\n/)
    .map(cleanMarkdown)
    .filter((paragraph) => paragraph && !paragraph.startsWith(">") && !paragraph.startsWith("##"));
  return paragraphs[0] ?? "";
}

function expansionFromBody(title: string, meaning: string): string | null {
  if (!/^[A-Z0-9][A-Z0-9+.-]+$/.test(title)) return null;
  const match = meaning.match(new RegExp(`^${escapeRegExp(title)} \\(([^)]+)\\)`));
  return match?.[1] ?? null;
}

function titleFromPath(path: string): string {
  return (path.split("/")[0] ?? "")
    .split("_")
    .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1))
    .join(" ");
}

function unquote(value: string): string {
  return value.replace(/^["']|["']$/g, "");
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

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
