# ADR 0014: Long-Tail Diagram Release Pacing

## Status

Accepted.

## Context

Phase 5 adds long-tail Mermaid diagram families after the core animated/static
surface exists. These roots vary widely in parser complexity, renderer fidelity,
animation support, docs impact, and compatibility risk.

The release policy needs to avoid two failure modes:

* Large bundled releases that make regressions hard to isolate.
* Tiny releases that ship parser-only support without enough fixtures, goldens,
  documentation, and migration notes.

`COVERAGE.md` already distinguishes partial, static-only, and unsupported roots,
and release-please maintains release notes from conventional commits.

## Decision

Ship long-tail diagram families one release at a time when they change user
visible support.

Each release that promotes a root to partial or static-only support must include:

* parser fixture coverage,
* static golden coverage,
* animation or static-collapse assertion,
* `COVERAGE.md` and docs updates,
* changelog/release notes via release-please,
* a demo asset when the change is visually meaningful.

Small fixes within an already-supported root can batch into normal patch/minor
releases. New root support should not be bundled monthly unless the roots are
mechanically coupled and share the same fixture/rendering proof.

## Consequences

* Regressions map cleanly to one promoted diagram family.
* The compatibility matrix stays honest per release.
* Release cadence depends on proof quality, not calendar batching.
* More release notes are required, but rollback and user communication are
  simpler.

## Rejected

* Bundled monthly root drops: attractive for marketing cadence, but they hide
  parser/render risk across unrelated grammars.
* Parser-only preview releases as supported roots: conflicts with the coverage
  policy that requires fixtures, goldens, and documented support level.
