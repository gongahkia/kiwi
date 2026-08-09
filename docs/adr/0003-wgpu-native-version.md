# ADR 0003: pin wgpu-native v29.0.1.1

## Decision

Pin the official `gfx-rs/wgpu-native` Linux x86_64 release `v29.0.1.1`, SHA-256 `95a4d90c071005a98d03eab348beaa6b07e16eb00d1dcdb9f8348f75eb97ec5a`.

## Rationale

The v29.0.1.1 release archive supplies both `libwgpu_native.so` and the authoritative `include/webgpu/webgpu.h` / `wgpu.h` used by the bridge and the narrow Lua FFI declarations. It is a recent official upstream release, and Vulkan is a first-class Linux wgpu backend.

## Dependency strategy

`make bootstrap` downloads only that archive from its official release URL, verifies its hash, and expands it under ignored `.deps/`. It does not commit binaries. To update, select a new upstream release, inspect its headers and release metadata, change version/URL/hash together in `script/bootstrap`, review the affected FFI ABI, then rerun `make check` and `make smoke`.
