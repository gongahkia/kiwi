# Plugin Authoring

This guide targets ABI `1.0` plugin packages. ABI 1 plugins are WebAssembly
components packaged with a manifest, a `.wasm` entry, declared capabilities, and
one extension point.

Runtime execution is host-owned. The package contract below is stable enough for
authors to build and publish test packages while the Wasmtime loader is wired.

## Package Layout

```text
kumeyuri-render-hello/
  kumeyuri.plugin.json
  plugin.wasm
  README.md
```

`kumeyuri.plugin.json`:

```json
{
  "name": "kumeyuri-render-hello",
  "version": "0.1.0",
  "abi": "1.0",
  "entry": "plugin.wasm",
  "kind": "render-backend",
  "capabilities": [],
  "exports": {
    "renderBackend": "hello"
  }
}
```

Required package metadata:

| Field | Meaning |
| --- | --- |
| `name` | Package identity used in cache paths and diagnostics |
| `version` | Plugin package semver |
| `abi` | Minimum required kumeyuri plugin ABI |
| `entry` | Relative `.wasm` component path inside the package |
| `kind` | `render-backend`, `diagram-type`, or `theme-transform` |
| `capabilities` | Explicit host capabilities requested before execution |
| `exports` | Extension point name exported by the component |

The host rejects absolute entries, `..` traversal, unknown ABI versions, unknown
capabilities, and missing kind-specific exports.

## Extension Kinds

| Kind | Required export | Purpose |
| --- | --- | --- |
| `render-backend` | `renderBackend` | Convert host frame timelines into an artifact |
| `diagram-type` | `diagramType` | Parse a custom root and lower it into frames |
| `theme-transform` | `themeTransform` | Transform a typed theme before rendering |

## Capabilities

Plugins start with no filesystem, network, environment, cache, clock, or random
access. Users grant capabilities explicitly:

```bash
kumeyuri render diagram.mmd --plugin-allow=fs.write,cache.read
```

ABI 1 capability names:

```text
fs.read
fs.write
net.fetch
env.read
cache.read
cache.write
clock.now
random.bytes
```

Request only the capabilities required for the extension point. A hello-world
render backend that only writes its artifact through host-managed blobs should
declare an empty capability list.

## Hello-World Render Backend

The hello-world backend returns a UTF-8 text artifact from the frame timeline it
receives. Its manifest declares no ambient host access:

```json
{
  "name": "kumeyuri-render-hello",
  "version": "0.1.0",
  "abi": "1.0",
  "entry": "plugin.wasm",
  "kind": "render-backend",
  "capabilities": [],
  "exports": {
    "renderBackend": "hello"
  }
}
```

Expected render response shape:

```json
{
  "artifact": "blob:artifact-1",
  "mediaType": "text/plain; charset=utf-8",
  "extension": "txt"
}
```

The plugin should write its bytes through the host blob API and return the blob
handle. It should not open output files itself unless `fs.write` was granted.

## Publishing

Publish the package to npm or crates.io with the `kumeyuri-plugin` keyword.

```bash
npm publish
cargo publish
```

Users install by package name:

```bash
kumeyuri plugin install kumeyuri-render-hello
```

`plugin install` resolves npm first, then crates.io. The resolved archive is
cached under `$XDG_DATA_HOME/kumeyuri/plugins/`, or
`$HOME/.local/share/kumeyuri/plugins/` if `XDG_DATA_HOME` is unset.

## Validation Checklist

- Manifest filename is `kumeyuri.plugin.json`.
- `entry` is a relative `.wasm` path inside the package.
- `abi` is `1.0`.
- `kind` and `exports` agree.
- Package keywords include `kumeyuri-plugin`.
- Capability list is minimal and uses only ABI 1 names.
- README documents supported formats, roots, or theme inputs.
