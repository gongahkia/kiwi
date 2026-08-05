#!/usr/bin/env tsx

import { readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";

import type { SearchEntry } from "@wat/search";

import { getPublicCorpusEntries } from "../apps/web/src/lib/public-corpus";
import { searchEntries } from "../apps/web/src/lib/search-core";

interface QueryFixture {
  query: string;
}

interface LatencyReport {
  base_url?: string;
  concurrency: number;
  measured_requests: number;
  p50_ms: number;
  p95_ms: number;
  p99_ms: number;
  search_entries?: number;
  team_entries?: number;
  target: string;
  warmup_requests: number;
}

const baseUrl = (process.env.WAT_BENCHMARK_URL ?? "http://localhost:3000").replace(/\/$/, "");
const warmupRequests = numberFromEnv("WAT_BENCHMARK_WARMUP", 1000);
const measuredRequests = numberFromEnv("WAT_BENCHMARK_REQUESTS", 1000);
const concurrency = numberFromEnv("WAT_BENCHMARK_CONCURRENCY", 1);
const teamEntryCount = numberFromEnv("WAT_BENCHMARK_TEAM_ENTRIES", 0);
const outputPath = process.env.WAT_BENCHMARK_OUTPUT;
const target = process.env.WAT_BENCHMARK_TARGET ?? "http";
let corpus: QueryFixture[] = [];
let coreEntries: SearchEntry[] | null = null;

void main();

async function main(): Promise<void> {
  corpus = JSON.parse(
    await readFile(
      new URL("../packages/search/fixtures/dev-tooling-acronyms.json", import.meta.url),
      "utf8"
    )
  ) as QueryFixture[];
  coreEntries =
    target === "web-core"
      ? [...(await getPublicCorpusEntries()), ...syntheticTeamEntries(teamEntryCount)]
      : null;

  await runPhase(warmupRequests, false);
  const latencies = await runPhase(measuredRequests, true);
  latencies.sort((left, right) => left - right);

  const report: LatencyReport = {
    concurrency,
    measured_requests: measuredRequests,
    p50_ms: percentile(latencies, 0.5),
    p95_ms: percentile(latencies, 0.95),
    p99_ms: percentile(latencies, 0.99),
    target,
    warmup_requests: warmupRequests
  };

  if (target === "http") {
    report.base_url = baseUrl;
  } else if (coreEntries) {
    report.search_entries = coreEntries.length;
    report.team_entries = teamEntryCount;
  }

  if (outputPath) {
    await writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`);
  }

  console.log(JSON.stringify(report, null, 2));
}

async function runPhase(total: number, record: boolean): Promise<number[]> {
  const latencies: number[] = [];
  let next = 0;

  await Promise.all(
    Array.from({ length: concurrency }, async () => {
      while (next < total) {
        const index = next;
        next += 1;
        const latency = await requestSearch(corpus[index % corpus.length]!.query);
        if (record) latencies.push(latency);
      }
    })
  );

  return latencies;
}

async function requestSearch(query: string): Promise<number> {
  if (target === "web-core") {
    return requestCoreSearch(query, coreEntries ?? []);
  }

  return requestHttpSearch(query);
}

function requestCoreSearch(query: string, entries: SearchEntry[]): number {
  const startedAt = performance.now();
  searchEntries({ entries, limit: 5, minConfidence: "T2", query });
  return performance.now() - startedAt;
}

function syntheticTeamEntries(count: number): SearchEntry[] {
  return Array.from({ length: count }, (_, index) => ({
    aliases: [],
    confidence_tier: "T2",
    contemporaries: [],
    domains: ["benchmark-team", `team-domain-${index % 50}`],
    expansions: [`Team Overlay Benchmark ${index}`],
    id: `benchmark-team-${index}`,
    layer: "team",
    meaning_short: `Synthetic team glossary benchmark entry ${index}.`,
    sources: [
      {
        license: "proprietary-team",
        publisher: "wat benchmark",
        retrieved_at: "2026-07-10T00:00:00.000Z",
        snippet: "Synthetic benchmark fixture.",
        source_quality: "community",
        title: "Team benchmark fixture",
        url: "https://example.test/wat/team-benchmark"
      }
    ],
    term: `WATTEAM${index}`,
    term_normalized: `watteam${index}`
  }));
}

async function requestHttpSearch(query: string): Promise<number> {
  const url = new URL("/api/v1/search", baseUrl);
  url.searchParams.set("q", query);
  url.searchParams.set("limit", "5");

  const startedAt = performance.now();
  const response = await fetch(url);
  await response.arrayBuffer();
  const elapsedMs = performance.now() - startedAt;

  if (!response.ok) {
    throw new Error(`GET ${url} failed with ${response.status}`);
  }

  return elapsedMs;
}

function percentile(values: number[], percentileValue: number): number {
  const index = Math.min(values.length - 1, Math.ceil(values.length * percentileValue) - 1);
  return Math.round(values[index]! * 100) / 100;
}

function numberFromEnv(name: string, fallback: number): number {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isFinite(value) || value < 1) return fallback;
  return Math.trunc(value);
}
