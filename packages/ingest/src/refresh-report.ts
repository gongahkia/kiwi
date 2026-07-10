import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  findPreviousDelta,
  summarizeDelta,
  type DeltaFile,
  type DeltaSummary
} from "./delta-summary.js";

export interface BenchmarkMetric {
  name: string;
  value: string;
}

export interface ParserErrorSummary {
  count: number;
  message: string;
  source: string;
}

export interface RefreshReport {
  benchmarks: BenchmarkMetric[];
  generatedAt: string;
  parserErrors: ParserErrorSummary[];
  sources: RefreshSourceReport[];
  totals: {
    added: number;
    changed: number;
    licenseChanges: number;
    parserErrors: number;
    removed: number;
  };
}

export interface RefreshSourceReport {
  added: number;
  changed: number;
  deltaPath: string;
  licenseChanges: number;
  qualitySample: string[];
  removed: number;
  source: string;
}

const rootDir = fileURLToPath(new URL("../../..", import.meta.url));

export function buildRefreshReport(input: {
  benchmarks?: BenchmarkMetric[];
  generatedAt?: string;
  parserErrors?: ParserErrorSummary[];
  sources: Array<{ deltaPath: string; summary: DeltaSummary }>;
}): RefreshReport {
  const sources = input.sources
    .map(({ deltaPath, summary }) => ({
      added: summary.added.length,
      changed: summary.changed.length,
      deltaPath,
      licenseChanges: summary.license_changes.length,
      qualitySample: summary.quality_samples.map((sample) => sample.term),
      removed: summary.removed.length,
      source: summary.source
    }))
    .sort((left, right) => left.source.localeCompare(right.source));
  const parserErrors = input.parserErrors ?? [];

  return {
    benchmarks: input.benchmarks ?? [],
    generatedAt: input.generatedAt ?? new Date().toISOString(),
    parserErrors,
    sources,
    totals: {
      added: sources.reduce((sum, source) => sum + source.added, 0),
      changed: sources.reduce((sum, source) => sum + source.changed, 0),
      licenseChanges: sources.reduce((sum, source) => sum + source.licenseChanges, 0),
      parserErrors: parserErrors.reduce((sum, error) => sum + error.count, 0),
      removed: sources.reduce((sum, source) => sum + source.removed, 0)
    }
  };
}

export function renderRefreshReport(report: RefreshReport): string {
  const sourceRows = report.sources.map(
    (source) =>
      `| ${escapeCell(source.source)} | ${source.added} | ${source.changed} | ${source.removed} | ${source.licenseChanges} | ${escapeCell(source.qualitySample.join(", ") || "none")} | ${escapeCell(source.deltaPath)} |`
  );
  const parserRows = report.parserErrors.map(
    (error) => `| ${escapeCell(error.source)} | ${error.count} | ${escapeCell(error.message)} |`
  );
  const benchmarkRows = report.benchmarks.map(
    (metric) => `| ${escapeCell(metric.name)} | ${escapeCell(metric.value)} |`
  );

  return [
    "# Corpus Refresh Report",
    "",
    `Generated: ${report.generatedAt}`,
    "",
    "| Metric | Count |",
    "| --- | ---: |",
    `| Added | ${report.totals.added} |`,
    `| Changed | ${report.totals.changed} |`,
    `| Removed | ${report.totals.removed} |`,
    `| License changes | ${report.totals.licenseChanges} |`,
    `| Parser errors | ${report.totals.parserErrors} |`,
    "",
    "## Source Deltas",
    "",
    "| Source | Added | Changed | Removed | License changes | Quality sample | Delta |",
    "| --- | ---: | ---: | ---: | ---: | --- | --- |",
    ...(sourceRows.length > 0 ? sourceRows : ["| none | 0 | 0 | 0 | 0 | none |  |"]),
    "",
    "## Parser Errors",
    "",
    "| Source | Count | Message |",
    "| --- | ---: | --- |",
    ...(parserRows.length > 0 ? parserRows : ["| none | 0 | none |"]),
    "",
    "## Benchmark Impact",
    "",
    "| Metric | Value |",
    "| --- | --- |",
    ...(benchmarkRows.length > 0 ? benchmarkRows : ["| none | not provided |"]),
    ""
  ].join("\n");
}

export function benchmarkMetrics(raw: unknown): BenchmarkMetric[] {
  if (!raw || typeof raw !== "object") return [];
  const value = raw as Record<string, unknown>;
  return ["target", "search_entries", "p50_ms", "p95_ms", "p99_ms", "measured_requests"]
    .filter((key) => value[key] != null)
    .map((key) => ({ name: key, value: String(value[key]) }));
}

export function parserErrorSummaries(raw: unknown): ParserErrorSummary[] {
  const errors = Array.isArray(raw)
    ? raw
    : raw && typeof raw === "object" && Array.isArray((raw as { errors?: unknown[] }).errors)
      ? (raw as { errors: unknown[] }).errors
      : [];
  return errors.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const error = item as Record<string, unknown>;
    const source = typeof error.source === "string" ? error.source : "unknown";
    const message = typeof error.message === "string" ? error.message : "parser error";
    const count = typeof error.count === "number" && Number.isFinite(error.count) ? error.count : 1;
    return [{ count, message, source }];
  });
}

async function reportFromDeltaPaths(
  deltaPaths: string[],
  options: { benchmarkPath?: string; errorsPath?: string } = {}
): Promise<RefreshReport> {
  const sources = [];
  for (const deltaPath of deltaPaths) {
    const resolved = resolveRepoPath(deltaPath);
    const current = JSON.parse(await readFile(resolved, "utf8")) as DeltaFile;
    sources.push({
      deltaPath,
      summary: summarizeDelta(current, await findPreviousDelta(resolved, current.source))
    });
  }
  return buildRefreshReport({
    benchmarks: options.benchmarkPath
      ? benchmarkMetrics(JSON.parse(await readFile(resolveRepoPath(options.benchmarkPath), "utf8")))
      : [],
    parserErrors: options.errorsPath
      ? parserErrorSummaries(
          JSON.parse(await readFile(resolveRepoPath(options.errorsPath), "utf8"))
        )
      : [],
    sources
  });
}

function escapeCell(value: string): string {
  return value.replaceAll("|", "\\|").replace(/\s+/g, " ").trim();
}

function parseArgs(argv: string[]): {
  benchmarkPath?: string;
  deltaPaths: string[];
  errorsPath?: string;
  outputPath: string;
} {
  const [outputPath, ...rest] = argv;
  if (!outputPath) throw new Error("usage: tsx src/refresh-report.ts <output-md> <delta-json...>");
  const deltaPaths: string[] = [];
  let benchmarkPath: string | undefined;
  let errorsPath: string | undefined;
  for (let index = 0; index < rest.length; index += 1) {
    const arg = rest[index];
    if (!arg) continue;
    const value = rest[index + 1];
    if (arg === "--benchmark") {
      if (!value) throw new Error("--benchmark requires a value");
      benchmarkPath = value;
      index += 1;
    } else if (arg === "--errors") {
      if (!value) throw new Error("--errors requires a value");
      errorsPath = value;
      index += 1;
    } else {
      deltaPaths.push(arg);
    }
  }
  if (deltaPaths.length === 0) throw new Error("at least one delta json is required");
  return { benchmarkPath, deltaPaths, errorsPath, outputPath };
}

function resolveRepoPath(path: string): string {
  return isAbsolute(path) ? path : join(rootDir, path);
}

if (process.argv[1]?.endsWith("refresh-report.ts")) {
  const { benchmarkPath, deltaPaths, errorsPath, outputPath } = parseArgs(process.argv.slice(2));
  const report = await reportFromDeltaPaths(deltaPaths, { benchmarkPath, errorsPath });
  const resolvedOutputPath = resolveRepoPath(outputPath);
  await mkdir(dirname(resolvedOutputPath), { recursive: true });
  await writeFile(resolvedOutputPath, renderRefreshReport(report));
}
