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

Checked on 2026-06-19 with:

```sh
gh issue list --state open --limit 100 --json number,title,state,labels,comments,updatedAt,url
```

Open issues:

| Issue | Labels | Triage state |
| --- | --- | --- |
| [#1 Public roadmap](https://github.com/gongahkia/kumeyuri/issues/1) | `documentation` | Triaged |

## Cadence

Run the triage check weekly. New issues older than seven days without a scope
label or maintainer response are overdue.
