import { readFile } from "node:fs/promises";

interface CoverageEntry {
  contemporaries?: string[];
  domains?: string[];
  id?: string;
  layer?: string;
}

interface Corpus {
  entries?: CoverageEntry[];
}

export interface ContemporariesCoverage {
  coveragePct: number;
  targetDomains: string[];
  total: number;
  withContemporaries: number;
}

const defaultTargetDomains = ["cloud", "devops", "observability", "storage"];
const defaultThresholdPct = 60;

export function calculateContemporariesCoverage(
  entries: CoverageEntry[],
  targetDomains = defaultTargetDomains
): ContemporariesCoverage {
  const targetDomainSet = new Set(targetDomains.map((domain) => domain.toLowerCase()));
  const targetEntries = entries.filter(
    (entry) =>
      entry.layer === "public" &&
      (entry.domains ?? []).some((domain) => targetDomainSet.has(domain.toLowerCase()))
  );
  const withContemporaries = targetEntries.filter(
    (entry) => (entry.contemporaries ?? []).length > 0
  ).length;

  return {
    coveragePct:
      targetEntries.length > 0
        ? Math.round((withContemporaries / targetEntries.length) * 100)
        : 100,
    targetDomains,
    total: targetEntries.length,
    withContemporaries
  };
}

async function main() {
  const corpusPath = process.argv[2] ?? "seeds/manual.json";
  const corpus = JSON.parse(await readFile(corpusPath, "utf8")) as Corpus;
  const coverage = calculateContemporariesCoverage(corpus.entries ?? []);

  if (coverage.coveragePct < defaultThresholdPct) {
    console.error(
      `contemporaries coverage ${coverage.coveragePct}% below ${defaultThresholdPct}%: ${coverage.withContemporaries}/${coverage.total} target entries`
    );
    process.exitCode = 1;
    return;
  }

  console.log(
    `contemporaries coverage ok: ${coverage.coveragePct}% (${coverage.withContemporaries}/${coverage.total} target entries)`
  );
}

if (import.meta.url === `file://${process.argv[1]}`) {
  void main();
}
