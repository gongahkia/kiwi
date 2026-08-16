# Nix package and development shell

Kiwi provides a flake for Linux x86_64. It pins Nixpkgs through the committed
`flake.lock` and fetches the same official `wgpu-native` v29.0.1.1 archive used
by the non-Nix bootstrap path, with the checked-in SHA-256. The flake does not
replace the Fedora-oriented Make workflow.

From a clean checkout with flakes enabled:

```sh
nix build .#kiwi
nix flake check
nix develop
make check
```

`nix build` writes `result`; run the package with `result/bin/kiwi` or inspect
local support data with `result/bin/kiwi doctor`. To install it into a user
profile, use `nix profile install .#kiwi`. The package forces the same release
mode as `make release`: development shader reload, renderer instrumentation,
and debug shortcuts remain disabled by default.

The dev shell includes the LuaJIT, compiler, `pkg-config`, terminfo, GLFW,
FreeType, HarfBuzz, Fontconfig, giflib, libpng, Vulkan-loader, and archive tools used by
the repository commands. It does not provide a running compositor, a Vulkan
driver, a binary cache, or cross-platform builds. A native window still needs a
working Linux Wayland/X11 session and compatible Vulkan driver.

To update the pinned dependency deliberately, run the following from a Nix
environment, review the complete lock-file diff and package changes, then run
the same build/check commands before committing:

```sh
nix flake lock --update-input nixpkgs
nix build .#kiwi
nix flake check
```

If Nix is not installed on a workstation, its flake commands cannot run there.
A disposable Nix environment is suitable for validating the package, but is not
a substitute for testing a real Linux display session and Vulkan driver. The
release and non-Nix `make check` paths remain supported workflows.
