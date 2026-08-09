# strok Rust bindings

`strok-sys` is intentionally raw generated FFI for the versioned C ABI. The
`strok` crate provides safe renderer ownership, borrowed RGB/RGBA color input,
optional depth and normal input, and read-only CellBuffer access. All safe image
views validate their layout against the C ABI and are borrowed only for a render
call.

For a development build, first build `build/core` with the C ABI target and run:

```sh
LD_LIBRARY_PATH="$PWD/build/core" cargo test --manifest-path bindings/rust/Cargo.toml
```

For an installed CMake package, set its prefix:

```sh
STROK_PREFIX=/path/to/strok-prefix \
  LD_LIBRARY_PATH=/path/to/strok-prefix/lib64 \
  cargo test --manifest-path bindings/rust/Cargo.toml
```

`STROK_INCLUDE_DIR` and `STROK_LIBRARY_DIR` can override those paths separately.
On platforms with a different dynamic-loader variable or install library
directory, use the corresponding values instead.
