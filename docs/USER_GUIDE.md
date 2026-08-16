# Kiwi user guide

Kiwi is a rendering-first terminal research platform for Linux x86_64. It is
useful for evaluating the implemented terminal and renderer contracts, but it
is not presented as a daily-driver terminal emulator or a complete
VT/xterm-compatible terminal. Read the [conformance matrix](CONFORMANCE.md)
before depending on a protocol feature.

## Install and start

### Source checkout

The Fedora 43 path is the maintained development workflow. From a clean
checkout, install the native prerequisites, bootstrap the pinned native
dependency, run the deterministic checks, and start Kiwi:

```sh
git clone https://github.com/gongahkia/kiwi.git
cd kiwi
sudo dnf install luajit gcc make curl unzip pkgconf-pkg-config ncurses \
  glfw-devel freetype-devel harfbuzz-devel giflib libpng-devel mesa-vulkan-drivers vulkan-loader-devel \
  vulkan-tools fontconfig google-noto-sans-mono-fonts
make bootstrap
make check
make run
```

`make run` builds the native bridge and the `kiwi` terminfo entry, then starts
an absolute `$SHELL`, or `/bin/sh` when `$SHELL` is not absolute. To start a
specific child, put it after `--`:

```sh
make run ARGS='-- /usr/bin/printf "Kiwi\n"'
```

The source workflow is not a system installation: the checkout is the launch
location and `make run` sets the project-local terminfo path for its child.

To display a remote PNG, APNG, or GIF, run the explicit URL helper from inside
that Kiwi shell. It fetches only a user-supplied HTTPS URL and then sends
Kiwi's bounded direct-image graphics stream; it does not make automatic network
requests and does not support video:

```sh
./script/kiwi-image https://images.example/kiwi.png
```

### Local release artifact

For a relocatable, release-mode Linux x86_64 artifact, use a clean checkout:

```sh
make release
release="kiwi-$(< VERSION)-linux-x86_64"
(cd dist && sha256sum --check "$release.tar.gz.sha256")
tar -xzf "dist/$release.tar.gz"
./"$release"/bin/kiwi --version
./"$release"/bin/kiwi -- /bin/sh
```

Inside the release terminal, use the installed helper for the same explicit
HTTPS PNG, APNG, or GIF path:

```sh
kiwi-image https://images.example/kiwi.png
```

Keep the extracted directory intact. Its launcher finds its own Lua source,
terminfo, WGPU library, and native surface bridge relative to `bin/kiwi`; it
does not install files into `/usr` or modify shell configuration. It still
requires system LuaJIT, GLFW, FreeType, HarfBuzz, Fontconfig, giflib, libpng, a Vulkan
loader and driver, and a working Linux Wayland or X11 session. The adjacent
checksum and `metadata.json` describe the artifact that was built.
The optional `kiwi-image` helper also requires `curl`, `zsh`, and standard GNU
core utilities from the host.

For a pinned Nix package or development shell, use [NIX.md](NIX.md). It has
the same Linux display/driver constraint and does not add a binary cache or
cross-platform support.

Arch/AUR publication is currently deferred; it is not an installation path.
See [AUR.md](AUR.md) for the evidence and the source, license, ownership, and
reproducible-build gates for reconsidering it.

## Configuration

Kiwi currently has no configuration-file search path and does not create a
`$XDG_CONFIG_HOME/kiwi` directory. Startup configuration is explicit
environment variables; change them in the invoking shell or a wrapper and
restart Kiwi. For example, a source checkout can use:

```sh
KIWI_FONT_FAMILY='Noto Sans Mono' \
KIWI_FONT_PX=18 \
KIWI_SCROLLBACK=4000 \
KIWI_AMBIGUOUS_WIDTH=2 \
make run
```

An extracted artifact accepts the same variables before its launcher:

```sh
KIWI_FONT_PX=18 ./kiwi-<version>-linux-x86_64/bin/kiwi -- /bin/sh
```

The documented startup settings are intentionally small:

| Variable | Default | Effect |
| --- | --- | --- |
| `KIWI_FONT` | unset | Readable `.ttf` font path, instead of Fontconfig family selection. |
| `KIWI_FONT_FAMILY` | `monospace` | Fontconfig primary family. |
| `KIWI_FONT_PX` | `20` | Base font pixel size before GLFW content-scale adjustment. |
| `KIWI_LIGATURES`, `KIWI_CALT` | disabled | Set either to `1` to request standard ligatures or contextual alternates. |
| `KIWI_AMBIGUOUS_WIDTH` | `1` | Ambiguous-width policy: use the documented `1` or `2` setting. |
| `KIWI_SCROLLBACK` | `2000` | Primary-screen retained line limit. |
| `KIWI_SELECTION_COLOR` | `#5E81AC70` | Selection highlight, `#RRGGBB` or `#RRGGBBAA`. |
| `KIWI_SEARCH_COLOR` | `#EBCB8B70` | Current scrollback-search highlight, in the same format. |
| `KIWI_HYPERLINK_COLOR` | `#88C0D0FF` | OSC 8 hyperlink underline, in the same format. |
| `KIWI_COMMAND_REGIONS` | disabled | Set to `1` for the built-in visible command/output separator pass. |
| `KIWI_COMMAND_REGION_COLOR` | `#88C0D055` | Command-region separator color, in the same format. |

Shell integration is separate and opt-in. The versioned Bash, Zsh, and fish
snippets only emit OSC 7/133 metadata when they are explicitly sourced in an
interactive `TERM=kiwi` shell with `KIWI_SHELL_INTEGRATION=1`; follow
[SHELL_INTEGRATION.md](SHELL_INTEGRATION.md) to enable or remove them.
The source checkout keeps those snippets in `integrations/v1/`; an extracted
artifact keeps the same versioned directory at `share/kiwi/integrations/v1/`.

### Release-mode defaults

The packaged launcher forces release mode. It ignores development shader reload
and keeps pass metrics/budgets, GPU timestamp instrumentation, renderer
inspector settings, and F2--F5 debug shortcuts off even if their corresponding
environment variables are inherited. `KIWI_DEVELOPMENT=1` is only a source
development route and requires an explicit `KIWI_DEV_SHADER_PATH`; it is not a
release customization mechanism. Trusted local render extensions remain an
explicit opt-in in either mode.

## Safe mode and support

To rule out every configured render extension, start with `--no-extensions`:

```sh
KIWI_RENDER_EXTENSIONS=local.example \
  make run ARGS='--no-extensions -- /bin/sh'
./kiwi-<version>-linux-x86_64/bin/kiwi --no-extensions -- /bin/sh
```

Safe mode bypasses the module list before any extension is loaded and also
bypasses extension-cap environment parsing. It does not disable built-in
terminal behavior, change the child command, or provide a sandbox for code
outside Kiwi. If the problem persists in safe mode, capture the smallest child
command that reproduces it.

`kiwi doctor` is the first support command. It is local and offline; its JSON
bundle is capped at 64 KiB and excludes terminal, clipboard, shell, and
arbitrary environment content. Review a bundle before sharing it:

```sh
make doctor ARGS='--json --bundle kiwi-support.json'
./kiwi-<version>-linux-x86_64/bin/kiwi doctor --json --bundle kiwi-support.json
```

The report is a fresh environment probe, not an attachment to a running
terminal session. It cannot recover terminal content or prior diagnostics.
[SUPPORT.md](SUPPORT.md) lists the report fields and the minimum useful issue
context.

## Maintained render-extension examples

Kiwi discovers no extension by default, has no marketplace, and makes no
network request to install one. The maintained API v1 examples are limited to
the two modules below. They are trusted local Lua code, not a security sandbox,
and neither can draw or allocate GPU resources under API v1.

| Module | API | Reads | What it demonstrates | Constraints |
| --- | --- | --- | --- | --- |
| `kiwi.renderer.samples.damage_observer` | v1 | `terminal.damage`, `frame.timing` | A semantic observer that requests one 250 ms redraw only after terminal damage. | It owns no GPU state or overlay and must not schedule another idle redraw. |
| `kiwi.renderer.samples.command_region_observer` | v1 | `terminal.command_regions`, `frame.timing` | A semantic observer that retains the current visible boundary count. | It owns no GPU state or drawing capability; useful boundaries require terminal OSC 133 data, such as the opt-in shell integration. |

Enable exactly one sample from a source checkout with `KIWI_RENDER_EXTENSIONS`:

```sh
KIWI_RENDER_EXTENSIONS=kiwi.renderer.samples.damage_observer \
  make run ARGS='-- /usr/bin/printf "sample extension\n"'

KIWI_COMMAND_REGIONS=1 \
KIWI_RENDER_EXTENSIONS=kiwi.renderer.samples.command_region_observer \
  make run
```

Set `KIWI_RENDER_EXTENSIONS` to a comma-separated list to opt into multiple
trusted modules. Disable all of them with `--no-extensions` as shown above, or
remove a module from that variable before restarting. API v1 requires every
declaration to use `api_version = 1`; a new API version needs an explicit
compatibility review rather than an assumed fallback.

`KIWI_EXTENSION_MAX_PASSES` limits optional passes (default `32`) and
`KIWI_EXTENSION_MAX_ANIMATION_HZ` limits optional redraw cadence (default
`60`, valid from `1/60` through `60`). A failing optional callback is disabled
for the current renderer lifetime; built-in passes remain separate. See
[RENDERER_API.md](RENDERER_API.md) for validation, lifecycle, diagnostics, and
the complete API v1 capability boundary.

## Current limits

Kiwi advertises a 16-colour terminfo contract and deliberately does not claim
truecolour terminfo extensions or `COLORTERM`. It is Linux x86_64-only and has
no implemented screen-reader adapter, primary selection, OSC 52 writes,
regular-expression search, full text indexing, command execution UI, or full
xterm/VT certification. The current, precise limits are maintained in the
[conformance matrix](CONFORMANCE.md), [text contract](TEXT.md),
[accessibility contract](ACCESSIBILITY.md), and the repository
[README](../README.md#deliberate-limits).
