# Launch checklist and draft copy

## Pre-launch checklist

- Pick launch date and owners.
- Invite 20 friendly testers; require at least 10 feedback responses before launch.
- Confirm hosted search p95 and k6 results are attached to the launch issue.
- Confirm browser extension, Slack app, and MCP server all work against the same hosted instance.
- Prepare screenshots/GIFs:
  - `docs/assets/ext-hover.gif`
  - `docs/assets/slack-demo.gif`
  - `docs/assets/mcp-demo.gif`
  - 60-second product hero video
- Prepare accounts/handles on X, Bluesky, Mastodon, and GitHub Discussions/Discord or Matrix.

## Draft Show HN title

Show HN: wat — a sourced glossary for tech acronyms, team jargon, and overloaded terms

## Draft Show HN opening comment

We built wat to answer the question every engineer hits in a new codebase, incident room, or Slack thread: “what does this acronym mean here?”

wat is a layered glossary for technical jargon:

- public corpus for common acronyms and overloaded engineering terms
- team layer for company/project-specific meanings
- source citations on every definition
- hybrid search using Postgres primitives
- browser extension for hover lookup
- Slack commands and shortcuts
- MCP server for assistant/tooling lookup
- self-host path with Postgres + Docker Compose

The important constraint: no AI-only unsourced definitions. If wat cannot cite the result, it should say so or queue a suggestion for review.

We are especially looking for feedback on:

1. ambiguous acronyms with multiple valid meanings
2. corpus quality/source citation gaps
3. browser extension and Slack workflow ergonomics
4. self-host setup pain points

Repo: <REPO_URL> Demo: <DEMO_URL>

## Launch response playbook

- Monitor comments for the first 4 hours after posting.
- Reply within 30 minutes during the peak window.
- Be transparent about limitations: corpus coverage, store review status, and hosted/self-host tradeoffs.
- Convert bug reports into GitHub issues with source links.
- Track stars, hosted searches, extension installs, Slack installs, MCP installs, and docs visits daily for 2 weeks.

## GitHub Discussions setup

Categories:

- Announcements
- Q&A
- Ideas
- Corpus/source requests
- Self-host support
- Integrations

Pinned welcome post:

```md
# Welcome to wat discussions

Use this space for corpus/source requests, integration ideas, self-host questions, and workflow feedback.

Before posting, include:

- surface: web, extension, Slack, Teams, Discord, MCP, API, self-host
- term or workflow affected
- expected meaning or behavior
- source URL when proposing a definition

Security issues should use private vulnerability reporting or the security contact, not public discussions.
```

## Monthly stats post template

```md
# wat monthly stats: <month>

- Stars:
- Hosted searches:
- No-result rate:
- Extension installs:
- Slack installs:
- MCP package downloads:
- New corpus entries:
- Top fixed issues:
- Next focus:
```

## Blog post outlines

### 1. wat: layered glossary for tech jargon

- Problem: same acronym means different things across teams/domains.
- Why citations matter.
- Public/team/personal layers.
- Surfaces: web, browser, Slack, MCP.
- What is deliberately out of scope.

### 2. Hybrid search with Postgres alone

- Why start with Postgres.
- Exact/fuzzy/full-text/vector scoring.
- Reciprocal rank fusion.
- Benchmark gates and latency checks.
- Operational simplicity for self-hosters.

### 3. Designing an MCP server for context-aware lookup

- Tool contract: lookup, list team acronyms, suggest definition.
- API-key/team scoping.
- Citation-shaped structured outputs.
- Write gating and suggestion queues.
- How assistants should handle unknown/unsourced terms.
