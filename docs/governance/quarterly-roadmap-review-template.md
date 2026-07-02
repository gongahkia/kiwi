# Quarterly Roadmap Review And Office Hours Template

Use this template once per quarter as an async GitHub Discussions thread. Keep
the thread open for at least seven days.

## Header

```text
Title: kumeyuri roadmap review and office hours: YYYY QN
Discussion category:
Opened:
Closes:
Facilitator:
```

## Scope

This thread is for roadmap feedback, prioritization, maintenance questions, and
community office-hours discussion. Security reports still go to `SECURITY.md`;
Code of Conduct reports still go to `CODE_OF_CONDUCT.md`.

## Current Roadmap Snapshot

Summarize the active quarter in five bullets or fewer.

* Current release target:
* Highest-risk work:
* Parser/rendering parity focus:
* Docs/community focus:
* Maintenance focus:

## Completed Since Last Review

| Area | Completed | Evidence |
| --- | --- | --- |
| Parser/layout | | |
| Renderers | | |
| CLI/API | | |
| Docs/site | | |
| Releases/distribution | | |
| Security/maintenance | | |

## Proposed Next Quarter Priorities

Rank no more than five priorities.

1. Priority:
   * Why:
   * Success evidence:
   * Known risk:
2. Priority:
   * Why:
   * Success evidence:
   * Known risk:
3. Priority:
   * Why:
   * Success evidence:
   * Known risk:

## Decisions Needed

List decisions that need maintainer or community input.

| Decision | Options | Default if no consensus | Deadline |
| --- | --- | --- | --- |
| | | | |

## Office-Hours Prompts

Answer any of these in the thread:

* What Mermaid syntax or output mismatch is blocking adoption?
* Which renderer matters most for your workflow: terminal, SVG, raster, WASM, or
  plugin?
* Which docs page was confusing or missing?
* Which release/distribution channel do you need?
* Which issue should be downgraded or removed from the roadmap?

## Triage Rules

During the review window:

* Tag comments as `bug`, `docs`, `parity`, `release`, `security`, `perf`,
  `integration`, or `question`.
* Convert actionable bug reports into issues.
* Convert broad proposals into RFC or ADR issues when the impact crosses public
  API, file format, security, or release policy.
* Do not promise dates unless a maintainer accepts ownership.

## Closeout

Before closing the thread:

* Post a decision summary.
* Link every created issue or ADR.
* Update GitHub issues or milestones if priorities changed.
* Update docs if a repeated question exposed a documentation gap.
* Capture unresolved questions for the next quarterly review.
