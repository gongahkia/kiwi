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

Checked on 2026-07-02 with:

```sh
gh issue list --state open --limit 100 --json number,title,state,labels,comments,updatedAt,url
```

Open issue groups:

| Issues | Labels | Triage state |
| --- | --- | --- |
| [#1 Public roadmap](https://github.com/gongahkia/kumeyuri/issues/1) | `documentation` | Living roadmap; keep open. |
| [#5](https://github.com/gongahkia/kumeyuri/issues/5), [#6](https://github.com/gongahkia/kumeyuri/issues/6), [#8](https://github.com/gongahkia/kumeyuri/issues/8)-[#21](https://github.com/gongahkia/kumeyuri/issues/21) | `release` | Blocked on registry/release credentials or publish events. |
| [#7](https://github.com/gongahkia/kumeyuri/issues/7), [#10](https://github.com/gongahkia/kumeyuri/issues/10), [#30](https://github.com/gongahkia/kumeyuri/issues/30) | `infra` | Blocked on domain/CDN/public directory registration access. |
| [#22](https://github.com/gongahkia/kumeyuri/issues/22)-[#25](https://github.com/gongahkia/kumeyuri/issues/25), [#27](https://github.com/gongahkia/kumeyuri/issues/27)-[#29](https://github.com/gongahkia/kumeyuri/issues/29) | `security` | Blocked on external program/signing/provenance state. |
| [#26](https://github.com/gongahkia/kumeyuri/issues/26) | `enhancement` | Needs manual screen-reader verification. |

## Cadence

Run the triage check weekly. New issues older than seven days without a scope
label or maintainer response are overdue.
