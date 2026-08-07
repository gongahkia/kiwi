# Packaging prototype

## Current selection

The measured macOS prototype uses [PyInstaller](https://pyinstaller.org/en/stable/usage.html)
in one-directory application-bundle mode. It preserves the existing Python and
pygame-ce application boundary, collects `kiwi.render` assets, and explicitly
bundles the Terminal mission and policy sources. PyInstaller builds are
platform-specific, so this macOS result is not evidence of Linux or Windows
support.

PyInstaller is intentionally not yet a `pyproject.toml` dependency. Adding and
locking a distribution dependency, its notices, signing identity, and release
automation needs a maintainer decision. The application remains usable from the
normal source checkout without it.

## Reproduce the macOS prototype

Run this from the repository root on an arm64 macOS host. `data_mapping` uses
braces because zsh otherwise interprets the unbraced `:examples` suffix as a
path modifier.

```zsh
repo_root="$PWD"
output_root="$(mktemp -d /tmp/kiwi-package.XXXXXX)"
data_mapping="${repo_root}/examples:examples"

uv run --with 'pyinstaller==6.21.0' --extra dev pyinstaller \
  --noconfirm --clean --windowed --name 'KIWI Terminal' \
  --paths "$repo_root/src" \
  --collect-data kiwi.render \
  --add-data="$data_mapping" \
  --osx-bundle-identifier com.gongahkia.kiwi \
  --target-architecture arm64 \
  --distpath "$output_root/dist" \
  --workpath "$output_root/build" \
  --specpath "$output_root/spec" \
  "$repo_root/src/kiwi/terminal.py"

codesign --verify --deep --strict "$output_root/dist/KIWI Terminal.app"
open "$output_root/dist/KIWI Terminal.app"
```

## Measured result

On 2026-08-07, the command completed on an Apple M3 running macOS 26.5.2 with
CPython 3.12.12. It produced a 40 MiB arm64 `KIWI Terminal.app` in about 14
seconds. `codesign --verify --deep --strict` passed; inspection reported an
ad-hoc signature (`TeamIdentifier=not set`). A dummy SDL launch probe stayed
running for four seconds, and the resulting bundle contained the Terminal
mission plus all shipped policy sources and render assets.

This is a packaging smoke test only. It is not a Developer ID signature,
notarized release, Gatekeeper acceptance test, visual acceptance test, or
cross-platform claim.

## Release gaps

- Obtain and configure a Developer ID Application certificate and appropriate
  entitlements, then sign every nested code object.
- Submit the signed artifact to Apple notarization and staple the ticket before
  making a macOS distribution claim.
- Decide whether to ship a DMG, ZIP, or PKG and automate a clean-host launch
  test and licence-notice inclusion.
- Measure and test separate Linux and Windows builds before representing either
  platform as supported.

Apple's notarization workflow is described in its
[notarization guidance](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution).
