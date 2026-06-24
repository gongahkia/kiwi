import { readFile } from "node:fs/promises";

interface Source {
  license?: string;
  url?: string;
}

interface Entry {
  confidence_tier?: string;
  id?: string;
  layer?: string;
  sources?: Source[];
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
    if (entry.layer !== "public") {
      continue;
    }

    const entryId = entry.id ?? "(missing id)";
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
  const corpusPath = process.argv[2] ?? "seeds/manual.json";
  const corpus = JSON.parse(await readFile(corpusPath, "utf8")) as Corpus;
  const issues = checkSourceCoverage(corpus);

  if (issues.length > 0) {
    for (const issue of issues) {
      console.error(`${issue.entryId}: ${issue.reason}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log(`source coverage ok: ${corpus.entries?.length ?? 0} entries checked`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  void main();
}
