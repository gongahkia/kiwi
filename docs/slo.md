# Service Level Objectives

## Scope

These SLOs apply to the hosted wat web/API service after launch.

## Availability

Objective: 99.5% monthly uptime for hosted web and lookup API.

SLI:

```text
successful_requests / total_requests
```

Successful requests are HTTP responses below `500`, excluding planned maintenance windows and synthetic requests that fail before reaching wat infrastructure.

Monthly error budget:

```text
0.5% of monthly request volume
```

## Latency

Objective: hosted search p95 below 500 ms end-to-end.

Primary lookup target remains stricter where benchmarked:

```text
GET /api/v1/search p95 < 150 ms server-side on hosted infra
```

SLI:

```text
p95(request_duration_ms{route="/api/v1/search"})
```

Measure warm traffic separately from cold starts. Exclude client network time when measuring server-side search latency.

## Freshness

Objective: public corpus refresh runs weekly and reviewed deltas are importable.

SLI:

```text
days_since_last_successful_corpus_refresh
```

Alert when the value exceeds 8 days.

## Error Budget Policy

When the monthly availability error budget is exhausted:

- pause non-critical launches
- prioritize reliability and rollback work
- review top error sources and recent deploys
- document mitigation in the incident log

## Reporting

Report monthly:

- availability SLI
- search p50/p95/p99
- error budget remaining
- incident count and time to mitigation
- corpus refresh freshness
