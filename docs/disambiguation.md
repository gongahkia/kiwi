# Disambiguation Rules

wat treats one query as a request for ranked meanings, not a request for one guessed definition. Every candidate keeps its sources and score breakdown.

## Ranking inputs

1. Term match: exact `term_normalized` match outranks alias, expansion, fuzzy, and full-text matches.
2. Layer priority: personal entries outrank team entries, and team entries outrank public entries when the same meaning is otherwise tied.
3. Domain overlap: explicit domain filters and team default domains boost candidates with matching `domains`.
4. Context match: surrounding text from the web app, browser extension, Slack, or MCP boosts entries whose term, expansion, domains, examples, and source snippets match that context.
5. Search score: BM25/full-text, vector similarity, and trigram similarity are combined with Reciprocal Rank Fusion.
6. Source quality: canonical sources outrank secondary sources, which outrank community sources.
7. Confidence tier: T1 outranks T2, T2 outranks T3, and T3 outranks T4.
8. Usage priors: team-local accepted suggestions and historical clicks may boost a candidate, but cannot hide higher-confidence sourced results.

## Tie-break order

Apply these only when candidates have the same final rounded score.

1. Exact normalized term match.
2. Higher layer priority: personal, then team, then public.
3. More matching domain labels.
4. Higher source quality: canonical, secondary, community.
5. Higher confidence tier: T1, T2, T3, T4.
6. More independent sources.
7. Newer `updated_at`.
8. Lexicographic `id` for deterministic output.

## Worked examples

### CAP

Query: `CAP`

Context: `distributed systems, partition tolerance, consistency`

Expected ordering:

1. CAP = Consistency, Availability, Partition tolerance
2. CAP = Common Agricultural Policy

Why: both candidates are exact term matches, but the distributed-systems domain and context terms boost the theorem entry.

### SLA

Query: `SLA`

Context: `incident review, uptime, customer contract`

Expected ordering:

1. SLA = Service Level Agreement
2. SLA = Stereolithography

Why: context terms match service reliability and contract language. If a team has a personal or team-specific SLA entry with the same meaning, that layer wins while preserving provenance.

### REST

Query: `REST`

Context: `HTTP API, resources, stateless`

Expected ordering:

1. REST = Representational State Transfer
2. REST = Restricted Environmental Stimulation Therapy

Why: the API context boosts the web-architecture expansion. If the user searches from a health-care domain with therapy context, the second entry can rank first.
