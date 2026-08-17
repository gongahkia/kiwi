# Public release contract

Kiwi releases are public, source-backed, tag-gated artifacts. The repository
uses the MIT license in [LICENSE](../LICENSE). Publishing a release still
requires the repository owner to make `github.com/gongahkia/kiwi` publicly
readable; a workflow cannot grant that external repository permission.

## Release input

A maintainer creates an annotated `vX.Y.Z` tag whose version exactly matches
`VERSION`. Pushing that tag runs `.github/workflows/release.yml`.

The workflow builds Linux x86_64 and macOS arm64 from the tagged source, runs
the established deterministic checks, verifies reproducibility with
`make release-check`, then creates one GitHub Release containing every file in
`dist/`: application archives, `libkiwi-vt` archives, and their SHA-256 files.
GitHub also provides the tagged source archive.

## Consumer verification

Consumers download an archive and its adjacent `.sha256` file from the GitHub
Release, run the checksum check described in the README, then invoke
`bin/kiwi --version`. The release artifact's metadata binds the version, Git
revision, source date, target, and pinned wgpu-native archive identity.

## Explicit limits

The macOS archive is ad-hoc signed only; Developer ID signing and notarization
remain future distribution work. Public release artifacts do not promote Kiwi
to daily-driver status: that requires the platform and manual evidence in the
compatibility ledger.
