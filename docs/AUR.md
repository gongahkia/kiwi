# Arch Linux AUR packaging decision

## Decision

Defer both a `PKGBUILD` and AUR publication. Kiwi does not currently provide a
public, anonymously fetchable immutable source archive or a license file, so a
recipe could not be reproduced by an AUR user or state a distribution license
truthfully. This repository intentionally contains no AUR remote, package
upload automation, binary distribution service, or telemetry.

The decision is based on the repository state observed on 2026-08-11, not an
assumption that the GitHub repository is public or private. A future
maintainer must repeat the checks below when the source-distribution contract
changes.

## Evidence and attempted validation

The current project `VERSION` is `0.1.0`, but `git tag` reports no source
release tags. A stable `kiwi` package therefore has no released upstream tag
to name in `pkgver`. A development `kiwi-git` package could only be considered
after the source is publicly fetchable at a fixed commit.

For the exact pushed commit
`daf3a80a659ef419b9d1e3b312818e61a4312ef9`, unauthenticated archive requests
returned HTTP `404` from both GitHub endpoints:

```sh
curl --location --silent --output /dev/null --write-out '%{http_code}\n' \
  https://github.com/gongahkia/kiwi/archive/daf3a80a659ef419b9d1e3b312818e61a4312ef9.tar.gz
curl --location --silent --output /dev/null --write-out '%{http_code}\n' \
  https://codeload.github.com/gongahkia/kiwi/tar.gz/daf3a80a659ef419b9d1e3b312818e61a4312ef9
```

Neither endpoint is a valid AUR source input in this state. The repository also
contains no `LICENSE`, `COPYING`, `NOTICE`, or equivalent license file. These
two facts block a public package independently of build tooling.

`makepkg`, `namcap`, and an Arch Linux container image were unavailable in the
validation environment. No local `makepkg` build was attempted because its
source verification would necessarily fail with the 404 above; that is
recorded as `No access` to a reproducible public source, rather than a passing
package validation.

The existing WGPU input is not the blocker: the build pins the official
`wgpu-native` v29.0.1.1 Linux x86_64 archive to SHA-256
`95a4d90c071005a98d03eab348beaa6b07e16eb00d1dcdb9f8348f75eb97ec5a`.

## Required path before proceeding

An authorized maintainer may add an AUR recipe only after all of these gates
are met:

1. Publish an immutable, anonymously downloadable source release or commit
   archive, and record its URL and verified SHA-256 in the `source` and
   `sha256sums` arrays. Do not use `SKIP` for either Kiwi or WGPU source
   integrity.
2. Add an explicit repository license and use its exact SPDX identifier in the
   package metadata.
3. Create an upstream version tag for a stable `kiwi` package. Until then, a
   separately named `kiwi-git` package must derive `pkgver` from a fixed commit
   and clearly remain a development snapshot.
4. Name an AUR-account holder who is explicitly authorized to own updates and
   adoption of the package. No such ownership or AUR publication authority is
   inferred from this repository.
5. Build as an unprivileged user in a disposable Arch environment with
   `makepkg --verifysource`, `makepkg`, and `namcap`; install the resulting
   package in a disposable system and run `kiwi --version`, `kiwi doctor
   --json`, and a bounded graphical smoke test when a Wayland/X11 session and
   compatible Vulkan driver are available.

The first gate follows the standard `source` and checksum contract documented
by [PKGBUILD(5)](https://man.archlinux.org/man/PKGBUILD.5.en). The build and
package stages should use `makepkg`, whose documented model keeps the package
stage in `fakeroot`; it must not run a package build as root. See
[makepkg(8)](https://man.archlinux.org/man/makepkg.8.en).

## Recipe design once unblocked

The future recipe should have explicit `pkgname`, `pkgver`, `pkgrel`,
`arch=('x86_64')`, `depends`, `makedepends`, `source`, and `sha256sums`, plus
separate `build()`, `check()`, and `package()` phases. It must list the WGPU
archive in `source` rather than invoke `make bootstrap` to make an unchecked
network request during the build.

The intended package layout is an FHS adaptation of the release artifact, not
a copy of the Nix package: `/usr/bin/kiwi` launches release mode;
`/usr/lib/kiwi/` holds the native surface bridge and pinned WGPU library;
`/usr/share/kiwi/lua/` holds Lua sources; and terminfo and documentation live
under `/usr/share/terminfo` and `/usr/share/doc/kiwi`. The package must not
write shell configuration or a Kiwi configuration file at install time.

Runtime dependencies need to cover the existing release contract (LuaJIT,
GLFW, FreeType, HarfBuzz, Fontconfig, giflib, libpng, the Vulkan loader, and a
user-selected compatible Vulkan driver). Build and test dependencies must be
derived from the actual `script/build-native`, `script/build-terminfo`, and
`make check` commands, then verified against the current Arch package
repository during the disposable build; do not copy Nix dependency names into
a PKGBUILD without that review.

## Maintenance and issue routing

The upstream repository maintainer remains responsible for source releases,
release checks, support-bundle privacy behavior, and application defects. The
explicitly authorized AUR maintainer would own `pkgrel` updates, source hashes,
dependency updates, and Arch-specific build fixes. A future AUR package page
may receive packaging-specific reports, but runtime and protocol defects
should be reported in this repository with the output of `kiwi doctor --json`
after review. If no authorized AUR owner, public source, license, or reproducible
Arch build exists, this deferral remains in force.
