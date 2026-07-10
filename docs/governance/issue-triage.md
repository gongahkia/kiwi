# Issue Triage

Incoming GitHub Issues are triaged within seven days.

## Triage Definition

An issue is triaged when it has:

- at least one scope label, such as `bug`, `documentation`, `enhancement`,
  `question`, `good first issue`, or `help wanted`;
- enough maintainer context to decide whether it is actionable, needs more
  information, is duplicate, or should be closed;
- a priority or roadmap link when the issue affects launch, security,
  compatibility, or release readiness.

## Current Check

Checked on 2026-07-10 with:

```sh
gh issue list --state open --limit 100 --json number,title,state,labels,comments,updatedAt,url
```

Open issue groups:

| Issues | Labels | Triage state |
| --- | --- | --- |
| [#1 Public roadmap](https://github.com/gongahkia/kumeyuri/issues/1) | `documentation` | Living roadmap; keep open. |
| [#5](https://github.com/gongahkia/kumeyuri/issues/5), [#6](https://github.com/gongahkia/kumeyuri/issues/6), [#8](https://github.com/gongahkia/kumeyuri/issues/8)-[#12](https://github.com/gongahkia/kumeyuri/issues/12), [#14](https://github.com/gongahkia/kumeyuri/issues/14), [#16](https://github.com/gongahkia/kumeyuri/issues/16), [#17](https://github.com/gongahkia/kumeyuri/issues/17), [#19](https://github.com/gongahkia/kumeyuri/issues/19)-[#21](https://github.com/gongahkia/kumeyuri/issues/21) | `release` | Placeholder/dry-run prep is done where possible; blocked on npm/crates credentials or missing release tags. |
| [#7](https://github.com/gongahkia/kumeyuri/issues/7), [#10](https://github.com/gongahkia/kumeyuri/issues/10), [#30](https://github.com/gongahkia/kumeyuri/issues/30) | `infra` | MCP metadata is prepared; blocked on domain/CDN access or public package/repository visibility. |
| [#22](https://github.com/gongahkia/kumeyuri/issues/22)-[#25](https://github.com/gongahkia/kumeyuri/issues/25), [#27](https://github.com/gongahkia/kumeyuri/issues/27), [#28](https://github.com/gongahkia/kumeyuri/issues/28) | `security` | Blocked on public repository visibility, external program submission, or signing/provenance state. |
| [#26](https://github.com/gongahkia/kumeyuri/issues/26) | `enhancement` | Automated a11y checks passed; needs manual screen-reader narration verification. |

## Cadence

Run the triage check weekly. New issues older than seven days without a scope
label or maintainer response are overdue.
