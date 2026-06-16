# Install

## Prerequisites

- Rust toolchain with Cargo.
- Node and npm for TypeScript package work and browser tests.
- `wasm32-unknown-unknown` target for WASM checks.
- `wasm-pack` when rebuilding browser WASM output.

```bash
rustup target add wasm32-unknown-unknown
cargo install wasm-pack --locked --version 0.13.1
```

## Source install

```bash
git clone https://github.com/gongahkia/kumeyuri.git
cd kumeyuri
cargo install --path crates/kumeyuri-cli
kumeyuri --help
```

## Run without installing

```bash
cargo run -q -p kumeyuri-cli -- render tests/snapshots/flowchart/input/02_two_nodes_linked.mmd
cargo run -q -p kumeyuri-cli -- play tests/snapshots/sequence/input/03_multiple_messages.mmd --loop
```

## Browser package from source

```bash
npm install
wasm-pack build crates/kumeyuri-render-wasm --target web --release --out-dir "../../site/pkg"
npm --workspace kumeyuri run build
```

`site/pkg` contains the generated wasm-bindgen files used by the static
playground.

## Verify the checkout

```bash
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo check --workspace --target wasm32-unknown-unknown
npm run test:ts-package
npm run test:web-component:browsers
npm run test:wasm-budget
```
