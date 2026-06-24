# Performance checks

## Hybrid search benchmark

Run the v0.1 search quality gate locally:

```sh
pnpm bench
```

The gate verifies the checked-in dev-tooling acronym corpus meets the TODO acceptance target:

- top-1 hit-rate >= 90%
- top-5 hit-rate >= 98%

## Server-side warm latency

Measure the web search path in-process, excluding HTTP/network overhead:

```sh
WAT_BENCHMARK_TARGET=web-core \
WAT_BENCHMARK_WARMUP=1000 \
WAT_BENCHMARK_REQUESTS=1000 \
WAT_BENCHMARK_OUTPUT=reports/$(date +%Y-%m)/warm-search-core-latency.json \
pnpm latency:search
```

## HTTP latency smoke test

Measure warm search latency against a running web app:

```sh
WAT_BENCHMARK_URL=http://localhost:3000 \
WAT_BENCHMARK_WARMUP=1000 \
WAT_BENCHMARK_REQUESTS=1000 \
WAT_BENCHMARK_OUTPUT=reports/$(date +%Y-%m)/search-latency.json \
pnpm latency:search
```

Use the hosted URL for the P1 hosted-latency TODO.

## k6 load test

Install k6, start or deploy the web app, then run:

```sh
WAT_BENCHMARK_URL=http://localhost:3000 \
WAT_K6_VUS=10 \
WAT_K6_DURATION=1m \
WAT_K6_P95_MS=200 \
pnpm load:search
```

For the P5 hosted gate, point `WAT_BENCHMARK_URL` at production and raise VUs until the run sustains 100 RPS while keeping p95 below 200 ms.
