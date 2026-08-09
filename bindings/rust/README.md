# strok Rust bindings

`strok-sys` is intentionally raw generated FFI for the versioned C ABI. It does
not provide a safe renderer wrapper or alter C ownership and borrowing rules.

For a development build, first build `build/core` with the C ABI target and run:

```sh
cargo test --manifest-path bindings/rust/Cargo.toml
```

For an installed CMake package, set its prefix:

```sh
STROK_PREFIX=/path/to/strok-prefix cargo test --manifest-path bindings/rust/Cargo.toml
```

`STROK_INCLUDE_DIR` and `STROK_LIBRARY_DIR` can override those paths separately.
