import { readdir, readFile, stat } from "node:fs/promises";
import { join } from "node:path";

interface Source {
  license?: string;
  url?: string;
}

interface Entry {
  confidence_tier?: string;
  id?: string;
  layer?: string;
  sources?: Source[];
  term?: string;
}

interface Corpus {
  entries?: Entry[];
}

export interface SourceCoverageIssue {
  entryId: string;
  reason: string;
}

export function checkSourceCoverage(corpus: Corpus): SourceCoverageIssue[] {
  const issues: SourceCoverageIssue[] = [];

  for (const entry of corpus.entries ?? []) {
    if (entry.layer && entry.layer !== "public") {
      continue;
    }

    const entryId = entry.id ?? entry.term ?? "(missing id)";
    const reviewOnly = entry.confidence_tier === "T4";
    if (!entry.sources || entry.sources.length === 0) {
      if (!reviewOnly) issues.push({ entryId, reason: "missing acceptable provenance" });
      continue;
    }

    for (const [index, source] of entry.sources.entries()) {
      if (!source.url) {
        if (!reviewOnly) issues.push({ entryId, reason: `source ${index} missing url` });
      }
      if (!source.license) {
        if (!reviewOnly) issues.push({ entryId, reason: `source ${index} missing license` });
      }
    }
  }

  return issues;
}

async function main() {
  const corpusPaths = process.argv.slice(2);
  const paths = corpusPaths.length > 0 ? corpusPaths : ["seeds/manual.json"];
  const entries = (await Promise.all(paths.map(readEntries))).flat();
  const issues = checkSourceCoverage({ entries });

  if (issues.length > 0) {
    for (const issue of issues) {
      console.error(`${issue.entryId}: ${issue.reason}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log(`source coverage ok: ${entries.length} entries checked`);
}

async function readEntries(path: string): Promise<Entry[]> {
  const info = await stat(path);
  if (info.isDirectory()) {
    const items = await readdir(path, { withFileTypes: true });
    return (
      await Promise.all(
        items
          .sort((left, right) => left.name.localeCompare(right.name))
          .map((item) => readEntries(join(path, item.name)))
      )
    ).flat();
  }
  if (!info.isFile() || !path.endsWith(".json")) return [];
  const corpus = JSON.parse(await readFile(path, "utf8")) as Corpus;
  return corpus.entries ?? [];
}

if (import.meta.url === `file://${process.argv[1]}`) {
  void main();
}
