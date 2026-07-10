# Project Identity Checks

Last checked: 2026-07-10.

## npm

`npm view @wat/core version --json` returned `E404`.

Status: `@wat/core` was not found from this machine. This does not reserve the `@wat` scope.

## Domains

`whois` returned `ACTIVE` for:

- `wat.dev`
- `getwat.dev`
- `wat.tools`

`dig` returned A/AAAA records for `wat.dev` and no A/AAAA records for `getwat.dev` or `wat.tools`.

Status: domain purchase/ownership is not verified from this repo.

## GitHub

`gh repo view wat/wat` could not resolve a repository. `gh api orgs/wat` returned `404` with the current token and also reported missing `admin:org` scope.

Status: GitHub org ownership/availability is not verified from this repo.
