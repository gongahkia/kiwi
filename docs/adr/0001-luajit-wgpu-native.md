# ADR 0001: LuaJIT application over wgpu-native

## Decision

Use LuaJIT as Kiwi's application language and call wgpu-native through LuaJIT FFI, with WGSL shaders and Vulkan selected for M0 Linux presentation.

## Rationale

This keeps the rendering architecture programmable in the language Kiwi will eventually expose while wgpu-native provides a portable GPU boundary. The M0 source remains overwhelmingly Lua; C is restricted to ABI-sensitive interop.

## Consequences

Lua owns terminal state, damage, atlas policy, pass orchestration, diagnostics, and benchmarks. FFI declarations are tied to the pinned header, and explicit resource cleanup is required instead of relying on GC ordering.
