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

## Developer Certificate of Origin

All pull request commits must include a DCO `Signed-off-by:` trailer.

Use `git commit -s` for new commits or `git commit --amend -s` for the latest
commit. The sign-off certifies the Developer Certificate of Origin 1.1:
<https://developercertificate.org/>.

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

Use `crates/kumeyuri-cli/locales/en-US.ftl` as the source catalog. Fluent-file PRs should add or
update `crates/kumeyuri-cli/locales/<locale>.ftl`, keep message ids aligned with `en-US.ftl`, wire
the locale in `crates/kumeyuri-cli/src/i18n.rs`, and include CLI verification.

If a Crowdin project is configured for the locale, link the project/export in
the issue. Otherwise, use a direct Fluent-file PR.

## AI-Generated Contributions

AI-assisted contributions are allowed when the contributor remains accountable
for the result.

Pull requests that use AI-generated code, tests, docs, fixtures, images, or
translations should disclose that in the PR description. Include the tool name
when practical and describe the human review performed.

Contributors must verify that AI-assisted changes:

* Match the requested issue or TODO scope.
* Build and pass the relevant tests.
* Do not include secrets, private data, copied proprietary code, or incompatible
  license text.
* Do not invent compatibility claims, benchmarks, security guarantees, or
  release status.
* Preserve attribution for third-party material.

Maintainers may ask for manual rewrites, smaller diffs, stronger tests, or
source citations when AI-assisted output is difficult to review.
