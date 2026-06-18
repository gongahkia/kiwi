# ADR 0010: WASM Plugin Host Runtime

## Status

Accepted.

## Context

RFC 0001 defines plugins as WASM components with an explicit ABI, typed
extension points, host-managed blobs, and deny-by-default capabilities. The host
runtime must support a Rust embedder, custom imports, explicit capability
grants, and a path to WIT/component-model bindings.

Inputs reviewed on 2026-06-18:

* Wasmtime `wasmtime::component` docs for component embedding, `Component`,
  component `Linker`, WIT `bindgen!`, and generated host traits:
  <https://docs.wasmtime.dev/api/wasmtime/component/index.html>.
* Component Model docs for Wasmtime command components, including default denial
  of filesystem and environment access:
  <https://component-model.bytecodealliance.org/running-components/wasmtime.html>.
* WASI introduction for capability-based sandboxing and explicit host grants:
  <https://wasi.dev/>.
* Wasmer Rust API docs for core module embedding, pluggable compilers, AOT/JIT,
  and interpreter options: <https://docs.rs/wasmer/latest/wasmer/>.
* wasm-bindgen CLI docs for generating JavaScript/TypeScript glue for browser,
  bundler, or Node.js targets:
  <https://rustwasm.github.io/docs/wasm-bindgen/reference/cli.html>.

## Decision

Use Wasmtime as the ABI 1.x plugin host runtime.

Implement plugins as WebAssembly components with a kumeyuri WIT world. Use
Wasmtime's component API in `kumeyuri-core::plugins` for compile, instantiate,
link, invoke, and host-call plumbing. Add WASI access only through explicit
kumeyuri capability grants; the default plugin store gets no filesystem,
network, environment, clock, random, or cache access beyond host-passed blob
handles.

ABI 1.x does not use Wasmer or wasm-bindgen-cli as the host runtime.

## Consequences

* The Rust host can generate WIT bindings for render backends, diagram types,
  theme transforms, and host calls instead of hand-rolling untyped exports.
* The runtime choice matches RFC 0001's component-model and capability-denial
  direction.
* Plugin execution stays server/CLI oriented. Browser-side plugin execution is
  out of scope for ABI 1.x and can be revisited with `jco` or JavaScript
  adapters later.
* Wasmtime adds a non-trivial dependency and compile-time cost to
  `kumeyuri-core`; keep it behind the plugin-runtime implementation path until
  the loader is wired.
* The host must own resource limits, compiled-component cache policy, package
  verification, and diagnostics. Wasmtime provides the sandbox/runtime, not the
  kumeyuri plugin policy.

## Rejected

* Wasmer: strong core module embedding story and customizable compiler options,
  but the current kumeyuri ABI is component/WIT-first and needs direct generated
  host bindings plus explicit capability linkage.
* wasm-bindgen-cli: useful for producing JS/TS glue for browser, bundler, and
  Node.js targets, but it is not a Rust CLI host runtime or capability policy
  layer.
* Native dynamic libraries: rejected by RFC 0001 for ABI 1.

## Revisit

Re-evaluate before ABI 2.0 if Wasmer's component-model host surface becomes a
better fit for kumeyuri's WIT world, or if browser-hosted plugins become a
release target.
