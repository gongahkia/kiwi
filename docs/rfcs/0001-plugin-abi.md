# RFC 0001: Plugin ABI Semantics

## Status

Draft.

## Summary

kumeyuri plugins are WASM components loaded by the host with an explicit ABI
version, a signed manifest, declared capabilities, and narrow extension points.
The first ABI should support three plugin classes:

- render backends that turn a validated frame timeline into an output artifact;
- diagram types that parse source, produce layout data, and lower into frames;
- theme transforms that map a built-in or user theme into adjusted colors.

The host remains responsible for file I/O, network denial, cache policy,
capability checks, parsing of core diagrams, and final CLI/user-facing errors.

## Goals

- Keep plugins deterministic by default.
- Make unsupported capabilities fail before plugin execution.
- Allow old plugins to keep running for the ABI major they target.
- Keep source parsing and rendering errors structured enough for CLI, editor,
  and CI integrations.
- Avoid exposing internal Rust structs as a stable binary contract.

## Non-goals

- No native dynamic libraries in ABI 1.
- No arbitrary filesystem, network, process, env, or clock access by default.
- No guarantee that plugin-rendered output visually matches core renderers.
- No stable Rust crate API yet; this RFC defines host/plugin wire semantics.

## Package Manifest

Each plugin package includes `kumeyuri.plugin.json`:

```json
{
  "name": "kumeyuri-render-pdf",
  "version": "0.1.0",
  "abi": "1.0",
  "entry": "plugin.wasm",
  "kind": "render-backend",
  "capabilities": [],
  "exports": {
    "renderBackend": "pdf"
  }
}
```

Required fields:

| Field | Meaning |
| --- | --- |
| `name` | Package identity used for cache and diagnostics. |
| `version` | Plugin package semver. |
| `abi` | Minimum required kumeyuri plugin ABI major/minor. |
| `entry` | WASM component path within the package. |
| `kind` | `render-backend`, `diagram-type`, or `theme-transform`. |
| `capabilities` | Explicit host grants requested before execution. |
| `exports` | Named extension points the host can register. |

The host rejects packages with missing fields, unknown ABI major versions,
unknown capabilities, or an entry outside the package root.

## ABI Versioning

ABI versions use `major.minor`.

- Same major and host minor >= plugin minor: load allowed.
- Same major and host minor < plugin minor: reject with an upgrade diagnostic.
- Different major: reject unless the host ships a compatibility adapter.

ABI 1.x promises additive changes only. Removing fields, changing wire types, or
changing host-call semantics requires ABI 2.0.

## ABI Deprecation Policy

Each ABI major has a minimum 24-month support window starting from the first
non-prerelease kumeyuri release that accepts that major. During that window,
the host keeps loading compatible plugins for that major according to the
version rules above.

Deprecation steps for an ABI major:

1. Announce the replacement ABI and migration path in release notes and docs.
2. Keep the old major loadable for the rest of its 24-month window.
3. Emit host diagnostics before removal once a newer stable ABI exists.
4. Remove or adapter-gate the old major only after the support window ends.

Minor ABI releases in a supported major remain additive. Plugin authors should
target the lowest minor version they need so older hosts can load their package.

## Wire Types

Plugins exchange data with the host as length-prefixed UTF-8 JSON envelopes.
Binary payloads are passed through host-managed blob handles.

Common envelope:

```json
{
  "abi": "1.0",
  "requestId": "01J00000000000000000000000",
  "payload": {}
}
```

Common error:

```json
{
  "kind": "parse-error",
  "message": "expected diagram header",
  "span": { "start": 0, "end": 8 },
  "hints": ["check the first non-comment line"]
}
```

Required error kinds:

| Kind | Use |
| --- | --- |
| `parse-error` | Source text is invalid for a diagram plugin. |
| `render-error` | Valid input cannot be rendered. |
| `unsupported` | Feature is known but not supported by the plugin. |
| `capability-denied` | Requested host call was not granted. |
| `internal` | Plugin failed unexpectedly. |

## Capabilities

ABI 1 defines denial defaults. A plugin receives no filesystem, network, env,
process, clock, random, or cache access unless explicitly granted.

Initial capability flags:

| Capability | Semantics |
| --- | --- |
| `fs.read` | Read files selected by the host. |
| `fs.write` | Write host-approved output files only. |
| `net.fetch` | Fetch host-approved URLs. |
| `env.read` | Read host-approved env vars. |
| `cache.read` | Read plugin cache entries. |
| `cache.write` | Write plugin cache entries. |
| `clock.now` | Read wall clock time. |
| `random.bytes` | Request random bytes from the host. |

The CLI grant surface should be explicit, for example:

```bash
kumeyuri render diagram.mmd --plugin render-pdf --plugin-allow=fs.write
```

## Extension Points

### Render Backend

Input:

```json
{
  "format": "pdf",
  "theme": "github",
  "frames": "blob:frames-1",
  "metadata": {
    "title": "diagram",
    "sourcePath": "docs/flow.mmd"
  }
}
```

Output:

```json
{
  "artifact": "blob:artifact-1",
  "mediaType": "application/pdf",
  "extension": "pdf"
}
```

Render backends consume the host's stable frame-timeline JSON, not private Rust
frame structs.

### Diagram Type

Input:

```json
{
  "source": "kanban\n  todo[Todo]",
  "root": "kanban",
  "options": {
    "theme": "github",
    "charset": "unicode"
  }
}
```

Output:

```json
{
  "diagnostics": [],
  "frames": "blob:frames-1",
  "defaultAnimation": "none"
}
```

Diagram plugins own parsing and layout for their custom roots. The host decides
which root names are registered and rejects collisions unless the user
explicitly overrides a core root.

### Theme Transform

Input:

```json
{
  "theme": "github",
  "colors": {
    "background": "#ffffff",
    "foreground": "#24292f"
  }
}
```

Output:

```json
{
  "colors": {
    "background": "#ffffff",
    "foreground": "#111111"
  }
}
```

Theme transforms may only return valid color/style values. They cannot mutate
source AST, layout, frame geometry, or renderer selection.

## Host Calls

All host calls are request/response and capability checked:

| Host call | Capability |
| --- | --- |
| `log(level, message)` | none |
| `blob.read(handle)` | none for handles the host passed in |
| `blob.write(mediaType, bytes)` | none |
| `cache.get(key)` | `cache.read` |
| `cache.put(key, blob)` | `cache.write` |
| `fs.read(pathHandle)` | `fs.read` |
| `fs.write(pathHandle, blob)` | `fs.write` |
| `fetch(urlHandle)` | `net.fetch` |
| `env.get(nameHandle)` | `env.read` |
| `clock.now()` | `clock.now` |
| `random.bytes(len)` | `random.bytes` |

The host may impose memory, CPU, output-size, and wall-clock limits on every
call. Limits must be included in diagnostics when they fail execution.

## Security Model

- Plugins run in a WASM sandbox.
- Capability grants are per invocation, not global.
- Package cache entries are namespaced by package name, package version, ABI
  major, and content hash.
- Plugin install verifies package checksums before execution.
- The host never passes raw user filesystem paths unless `fs.read` or `fs.write`
  was granted for that path.
- The host records plugin name/version/ABI in render metadata for auditability.

## Open Questions

- Whether ABI 1 should use the WebAssembly Component Model from day one or a
  simpler core WASM C ABI with JSON envelopes.
- Whether signed plugin packages are required before public plugin install ships
  or only before trusted-plugin badges.
- Whether diagram plugins should return frame timelines directly or a stable
  intermediate layout graph.

## Acceptance Criteria

- `kumeyuri_abi` can encode ABI version, manifest, capability flags, and common
  error envelopes.
- The plugin loader rejects unknown ABI majors and ungranted capabilities before
  execution.
- At least one render-backend plugin can render from a host-provided frame
  timeline without access to internal Rust structs.
- Plugin smoke tests can load a package, render a sample, and diff the result.
