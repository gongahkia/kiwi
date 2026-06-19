#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";

const baseUrl = (process.env.WAT_BENCHMARK_URL ?? "http://localhost:3000").replace(/\/$/, "");
const warmupRequests = numberFromEnv("WAT_BENCHMARK_WARMUP", 1000);
const measuredRequests = numberFromEnv("WAT_BENCHMARK_REQUESTS", 1000);
const concurrency = numberFromEnv("WAT_BENCHMARK_CONCURRENCY", 1);
const outputPath = process.env.WAT_BENCHMARK_OUTPUT;
const target = process.env.WAT_BENCHMARK_TARGET ?? "http";
const corpus = JSON.parse(
  await readFile(
    new URL("../packages/search/fixtures/dev-tooling-acronyms.json", import.meta.url),
    "utf8"
  )
);

await runPhase(warmupRequests, false);
const latencies = await runPhase(measuredRequests, true);
latencies.sort((left, right) => left - right);

const report = {
  base_url: baseUrl,
  concurrency,
  measured_requests: measuredRequests,
  p50_ms: percentile(latencies, 0.5),
  p95_ms: percentile(latencies, 0.95),
  p99_ms: percentile(latencies, 0.99),
  target,
  warmup_requests: warmupRequests
};

if (outputPath) {
  await writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`);
}

console.log(JSON.stringify(report, null, 2));

async function runPhase(total, record) {
  const latencies = [];
  let next = 0;

  await Promise.all(
    Array.from({ length: concurrency }, async () => {
      while (next < total) {
        const index = next;
        next += 1;
        const latency = await requestSearch(corpus[index % corpus.length].query);
        if (record) latencies.push(latency);
      }
    })
  );

  return latencies;
}

async function requestSearch(query) {
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

function percentile(values, percentileValue) {
  const index = Math.min(values.length - 1, Math.ceil(values.length * percentileValue) - 1);
  return Math.round(values[index] * 100) / 100;
}

function numberFromEnv(name, fallback) {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isFinite(value) || value < 1) return fallback;
  return Math.trunc(value);
}
