import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { MarkupKind, type Hover, type Position } from "vscode-languageserver/node";

interface WatSource {
  title: string;
  url: string;
}

interface WatEntry {
  aliases: string[];
  domains: string[];
  expansions: string[];
  id: string;
  layer: string;
  meaning_short: string;
  sources: WatSource[];
  term: string;
  term_normalized: string;
}

async function readSeedJson(): Promise<string> {
  for (const seedPath of [
    process.env.WAT_SEED_PATH,
    join(process.cwd(), "packages/ingest/seeds/manual.json"),
    join(process.cwd(), "../../packages/ingest/seeds/manual.json")
  ]) {
    if (!seedPath) {
      continue;
    }
    try {
      return await readFile(seedPath, "utf8");
    } catch {
      continue;
    }
  }

  throw new Error("manual seed file not found; set WAT_SEED_PATH");
}

async function getPublicEntries(): Promise<WatEntry[]> {
  const parsed = JSON.parse(await readSeedJson()) as { entries: WatEntry[] };
  return parsed.entries.filter((entry) => entry.layer === "public");
}

export function tokenAtPosition(text: string, position: Position): string | null {
  const line = text.split(/\r?\n/)[position.line];
  if (!line) {
    return null;
  }

  let start = Math.min(position.character, line.length);
  let end = start;
  const tokenChar = /[A-Za-z0-9+#.-]/;

  while (start > 0 && tokenChar.test(line[start - 1] ?? "")) {
    start -= 1;
  }
  while (end < line.length && tokenChar.test(line[end] ?? "")) {
    end += 1;
  }

  const token = line.slice(start, end);
  return token ? token : null;
}

function formatHover(entry: WatEntry): Hover {
  const expansion = entry.expansions[0] ?? entry.term;
  const source = entry.sources[0];
  const sourceLine = source ? `\n\nSource: [${source.title}](${source.url})` : "";

  return {
    contents: {
      kind: MarkupKind.Markdown,
      value: `**${entry.term}** - ${expansion}\n\n${entry.meaning_short}${sourceLine}`
    }
  };
}

export async function hoverForToken(token: string): Promise<Hover | null> {
  const normalized = token.toLowerCase();
  const entries = await getPublicEntries();
  const entry = entries.find(
    (candidate) =>
      candidate.term_normalized === normalized ||
      candidate.aliases.some((alias) => alias.toLowerCase() === normalized)
  );

  return entry ? formatHover(entry) : null;
}

export async function hoverAtPosition(text: string, position: Position): Promise<Hover | null> {
  const token = tokenAtPosition(text, position);
  return token ? hoverForToken(token) : null;
}
