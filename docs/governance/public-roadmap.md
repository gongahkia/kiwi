# Public Roadmap

Last reviewed: 2026-07-10.

This issue tracks public roadmap priorities and is updated monthly.

## July 2026 Update

Completed since the last review:

- [#2](https://github.com/gongahkia/kumeyuri/issues/2): install troubleshooting docs, closed by `b55b1f5`.
- [#3](https://github.com/gongahkia/kumeyuri/issues/3): quoted flowchart punctuation fixture, closed by `7e0d96d`.
- [#4](https://github.com/gongahkia/kumeyuri/issues/4): MCP smoke-test docs, closed by `94216bb`.
- [#15](https://github.com/gongahkia/kumeyuri/issues/15): render action `v1` release, closed by `0dad50d`.
- [#18](https://github.com/gongahkia/kumeyuri/issues/18): `v1.1.0-plugins` GitHub prerelease, closed by `45ea487`.
- [#29](https://github.com/gongahkia/kumeyuri/issues/29): security PGP status verified, closed by `72d6de9`.

Verified current external state on 2026-07-10:

- GitHub releases `v1` and `v1.1.0-plugins` are published.
- `kumeyuri`, `remark-kumeyuri`, and `rehype-kumeyuri` are not published on npm.
- `cargo search kumeyuri` returned no matching crate.
- Placeholder `kumeyuri` crate metadata is prepared in `b53d61c`; crates.io
  publish is blocked on credentials.
- npm package dry-runs pass for `kumeyuri`, `remark-kumeyuri`, and
  `rehype-kumeyuri`; npm publish is blocked on authentication.
- `kumeyuri.dev` has no DNS records.
- `npm run release:trust` passes for repository release-trust metadata.
- Official MCP Registry metadata is prepared in `c008fee`; directory
  submissions are blocked on public package/repository visibility.
- Release publish order and credential gates are documented in `eeefaa4`.
- Web-component axe and keyboard accessibility checks pass; NVDA, VoiceOver,
  and JAWS narration still need manual verification.
- Current `v1.1.0-plugins` release assets do not yet have Sigstore bundles or
  GitHub provenance attestations.
- The repository is private; OSS-Fuzz and public MCP directory registration need
  public source visibility before submission.

## Active Priorities

1. Finish release/distribution readiness: [#5](https://github.com/gongahkia/kumeyuri/issues/5), [#6](https://github.com/gongahkia/kumeyuri/issues/6), [#8](https://github.com/gongahkia/kumeyuri/issues/8)-[#12](https://github.com/gongahkia/kumeyuri/issues/12), [#14](https://github.com/gongahkia/kumeyuri/issues/14), [#16](https://github.com/gongahkia/kumeyuri/issues/16), [#17](https://github.com/gongahkia/kumeyuri/issues/17), [#19](https://github.com/gongahkia/kumeyuri/issues/19)-[#21](https://github.com/gongahkia/kumeyuri/issues/21).
2. Finish infrastructure setup: [#7](https://github.com/gongahkia/kumeyuri/issues/7), [#10](https://github.com/gongahkia/kumeyuri/issues/10), [#30](https://github.com/gongahkia/kumeyuri/issues/30).
3. Complete manual accessibility verification: [#26](https://github.com/gongahkia/kumeyuri/issues/26).
4. Strengthen governance/security: [#22](https://github.com/gongahkia/kumeyuri/issues/22)-[#25](https://github.com/gongahkia/kumeyuri/issues/25), [#27](https://github.com/gongahkia/kumeyuri/issues/27), [#28](https://github.com/gongahkia/kumeyuri/issues/28).

## Monthly Update Checklist

- [x] Review open launch/release/governance issues.
- [x] Summarize completed work with links to commits, issues, releases, or docs.
- [x] Add or remove priorities based on shipped work and issue feedback.
- [x] Link high-signal issues under the relevant priority.
- [x] Update this issue no later than the first week of the month.

## Source of Truth

Detailed task tracking is in GitHub Issues. `TODO.md` is not present in the
current checkout.
