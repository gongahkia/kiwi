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

## Troubleshooting

If Cargo commands fail because Rust is missing or too old, install the stable
toolchain and verify the active compiler:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
rustup default stable
rustc --version
cargo --version
```

If WASM budget checks fail because `wasm-pack` is missing, install the pinned
tool:

```bash
cargo install wasm-pack --locked --version 0.13.1
wasm-pack --version
```

If docs builds fail because `mdbook` is missing, install it before running the
docs command:

```bash
cargo install mdbook --locked
mdbook --version
npm run docs:build
```

If npm workspace tests fail with missing packages or unresolved workspace
imports, install dependencies from the repository root:

```bash
npm install
npm run test:ts-package
```

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
