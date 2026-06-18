# Contributing

## Branch Flow

Use short-lived branches from `main`:

1. Sync `main`.
2. Create `type/scope-summary`, for example `feat/parser-flowchart`.
3. Keep the diff focused on one issue or one TODO item.
4. Open a pull request into `main`.
5. Rebase or merge latest `main` before review if the branch drifts.

Do not commit generated build output unless a release task explicitly requires
it.

## Commit Style

Use Conventional Commits:

```text
<type>(<scope>): <summary>
```

Common types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`,
`ci`, `chore`.

Examples:

```text
feat(parser): parse flowchart directives
fix(svg): escape label text
docs: add embedding guide
```

Use `BREAKING CHANGE:` in the commit body for incompatible API or CLI changes.

## Review Expectations

Pull requests should include:

* Linked issue or TODO item.
* What changed and why.
* Tests or verification commands run.
* Screenshots or visual diffs when any renderer output changes.
* Notes for known gaps, follow-up work, or intentional tradeoffs.

Review should check behavior, security, parser compatibility, renderer output,
accessibility impact, and whether the change stays inside the requested scope.

## Translation Contributions

Open a Translation issue before starting a new locale or broad terminology
review.

Use `locales/en-US.ftl` as the source catalog. Fluent-file PRs should add or
update `locales/<locale>.ftl`, keep message ids aligned with `en-US.ftl`, wire
the locale in `crates/kumeyuri-cli/src/i18n.rs`, and include CLI verification.

If a Crowdin project is configured for the locale, link the project/export in
the issue. Otherwise, use a direct Fluent-file PR.
