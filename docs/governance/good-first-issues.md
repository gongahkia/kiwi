# Good First Issue Queue

The project keeps a small GitHub Issues queue labeled `good first issue`.

Current queue opened on 2026-06-19:

| Issue | Scope |
| --- | --- |
| [#2](https://github.com/gongahkia/kumeyuri/issues/2) | Install troubleshooting docs |
| [#3](https://github.com/gongahkia/kumeyuri/issues/3) | Flowchart quoted-label fixture |
| [#4](https://github.com/gongahkia/kumeyuri/issues/4) | MCP smoke-test docs |

## Response Policy

First-time contributors should receive a maintainer response within 48 hours.
When a first-time contributor comments or opens a PR:

1. thank them for the specific contribution;
2. confirm whether the issue is still available;
3. point to the relevant test command;
4. label blockers clearly instead of leaving the thread idle.

Run this weekly:

```sh
gh issue list --state open --label "good first issue" --json number,title,updatedAt,url
```
