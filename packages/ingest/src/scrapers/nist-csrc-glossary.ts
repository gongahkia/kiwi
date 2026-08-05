import { execFile as execFileCallback } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

import type { RawEntry, ScraperPlugin } from "../scraper.js";

type NistDefinitionSource = {
  link?: string;
  note?: string;
  text?: string;
};

type NistDefinition = {
  sources?: NistDefinitionSource[];
  text?: string;
};

type NistParentTerm = {
  definitions?: NistDefinition[] | null;
  link?: string;
  term?: string;
};

type NistGlossaryExport = {
  parentTerms?: NistParentTerm[];
};

const execFile = promisify(execFileCallback);
const sourceName = "nist-csrc-glossary";
const zipUrl = "https://csrc.nist.gov/csrc/media/glossary/glossary-export.zip";
const jsonFileName = "glossary-export.json";

export const nistCsrcGlossaryScraper: ScraperPlugin = {
  name: sourceName,
  license: "NIST-PD",
  refresh_interval: "daily",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const data = await fetchGlossaryExport();

    for (const entry of jsonToRawEntries(data, retrievedAt)) {
      yield entry;
    }
  }
};

export function jsonToRawEntries(data: NistGlossaryExport, retrievedAt: string): RawEntry[] {
  return (data.parentTerms ?? []).flatMap((parentTerm): RawEntry[] => {
    const term = cleanHtml(parentTerm.term ?? "");
    if (!term || !/[\p{Letter}\p{Number}]/u.test(term)) return [];

    return (parentTerm.definitions ?? []).flatMap((definition): RawEntry[] => {
      const meaning = cleanHtml(definition.text ?? "");
      if (!meaning) return [];

      return [
        {
          domains: ["nist", "security", "privacy"],
          expansion: term,
          meaning,
          sources: [
            {
              license: "NIST-PD",
              publisher: "NIST CSRC Glossary",
              retrieved_at: retrievedAt,
              snippet: meaning,
              source_quality: "canonical",
              title: sourceTitle(term, definition.sources ?? []),
              url: parentTerm.link ?? "https://csrc.nist.gov/glossary"
            }
          ],
          term
        }
      ];
    });
  });
}

async function fetchGlossaryExport(): Promise<NistGlossaryExport> {
  const dir = await mkdtemp(join(tmpdir(), "wat-nist-glossary-"));
  const zipPath = join(dir, "glossary-export.zip");

  try {
    const response = await fetch(zipUrl);
    if (!response.ok) {
      throw new Error(`failed to fetch ${zipUrl}: ${response.status}`);
    }
    await writeFile(zipPath, Buffer.from(await response.arrayBuffer()));
    const { stdout } = await execFile("unzip", ["-p", zipPath, jsonFileName], {
      maxBuffer: 16 * 1024 * 1024
    });
    return JSON.parse(stdout.replace(/^\uFEFF/, "")) as NistGlossaryExport;
  } finally {
    await rm(dir, { force: true, recursive: true });
  }
}

function sourceTitle(term: string, sources: NistDefinitionSource[]): string {
  const refs = sources.map((source) => cleanHtml(source.text ?? "")).filter(Boolean);
  return refs.length > 0
    ? `NIST CSRC glossary: ${term} (${refs.join("; ")})`
    : `NIST CSRC glossary: ${term}`;
}

function cleanHtml(input: string): string {
  return decodeHtmlEntities(
    input
      .replace(/<br\s*\/?>/gi, " ")
      .replace(/<\/(?:p|li|div|ol|ul|sub|sup)>/gi, " ")
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
