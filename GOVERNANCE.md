# Governance

kumeyuri is currently maintained by the project owner. This policy defines how
additional maintainers are added once repeat contributors exist.

## Roles

### Triager

Triagers help keep issues actionable.

Permissions:

* Label, de-duplicate, and close stale issues.
* Request reproduction cases, fixture inputs, and version details.
* Mark bugs by severity and affected area.

Requirements:

* At least three useful issue reports, reproductions, docs fixes, or test-case
  contributions.
* Consistent use of the Code of Conduct and contributor guidelines.
* No direct commit or release access.

### Committer

Committers may merge routine changes after review.

Permissions:

* Review and merge non-release pull requests.
* Maintain tests, docs, fixtures, examples, and integrations.
* Backport security or release fixes only with maintainer approval.

Requirements:

* Sustained contribution over at least two months.
* At least five accepted pull requests, including one test or docs improvement.
* Demonstrated judgment on parser compatibility, renderer output, security, and
  accessibility risk.
* Approval by at least one maintainer.

### Maintainer

Maintainers own project direction and release authority.

Permissions:

* Approve roadmap changes, release plans, compatibility claims, and public
  security advisories.
* Manage repository settings, branch protection, package publishing, and signing
  keys.
* Add or remove triagers and committers.

Requirements:

* Sustained contribution over at least six months.
* Proven ability to review cross-cutting changes across CLI, parser, renderer,
  docs, release, and security surfaces.
* Approval by a majority of current maintainers. While there is only one
  maintainer, approval is by that maintainer.

## Decision Process

Most technical decisions happen in pull requests. Changes with broad API,
format, compatibility, security, or release impact should start as an issue,
ADR, or RFC before implementation.

Maintainers aim for consensus. If consensus is not possible, maintainers vote.
Each maintainer has one vote. A change passes with a simple majority unless it
changes security policy, governance, or release signing; those require a
two-thirds majority once the project has three or more maintainers.

## Conflict Handling

Contributors with a direct conflict of interest should disclose it before
reviewing or approving related work. A maintainer should not be the sole approver
of a change that affects their own external package, service, employer, or paid
engagement.

Code of Conduct reports follow `CODE_OF_CONDUCT.md`; security reports follow
`SECURITY.md`.

## Inactivity

A triager, committer, or maintainer may be moved to emeritus status after six
months without project activity. Access can be restored by maintainer approval
when activity resumes.

## Release Authority

Until multi-maintainer signing is implemented, releases are cut by the project
owner. After threshold signing exists, release approval requires at least two
maintainers and the configured signing threshold.
