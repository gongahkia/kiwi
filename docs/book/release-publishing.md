# Release Publishing

Use this runbook only from a clean checkout on the release commit.

## Auth Gates

Verify credentials before publishing:

```bash
npm whoami
test -n "${CARGO_REGISTRY_TOKEN:-}" || test -f "$HOME/.cargo/credentials.toml"
gh auth status
```

If any gate fails, stop. Dry-runs can still validate packaging, but they do not
reserve names or publish artifacts.

## Current External Checks

```bash
cargo search kumeyuri --limit 10
npm view kumeyuri version --json
npm view remark-kumeyuri version --json
npm view rehype-kumeyuri version --json
dig +short kumeyuri.dev
```

An empty crates.io search, npm `E404`, or empty DNS response means the external
asset is still unpublished or unconfigured.

## Crates.io

Run dry-runs first:

```bash
cargo publish --dry-run --manifest-path crates/kumeyuri/Cargo.toml
cargo package --manifest-path crates/kumeyuri-core/Cargo.toml
```

Publish workspace crates in dependency order:

```bash
cargo publish --manifest-path crates/kumeyuri/Cargo.toml
cargo publish --manifest-path crates/kumeyuri-core/Cargo.toml
cargo publish --manifest-path crates/kumeyuri-render-svg/Cargo.toml
cargo publish --manifest-path crates/kumeyuri-render-tui/Cargo.toml
cargo publish --manifest-path crates/kumeyuri-render-raster/Cargo.toml
cargo publish --manifest-path crates/kumeyuri-render-wasm/Cargo.toml
cargo publish --manifest-path crates/mdbook-kumeyuri/Cargo.toml
cargo publish --manifest-path crates/kumeyuri-cli/Cargo.toml
```

`kumeyuri-cli` cannot package for crates.io until `kumeyuri-core` and the
renderer crates it depends on are already available from crates.io.

## npm

Use the npm publish workflow when possible so provenance and SBOM generation
stay in CI:

```bash
gh workflow run npm-publish.yml --ref main
```

Local dry-runs:

```bash
npm_config_cache=/tmp/kumeyuri-npm-cache npm publish --dry-run --workspace kumeyuri --access public
npm_config_cache=/tmp/kumeyuri-npm-cache npm publish --dry-run --workspace rehype-kumeyuri --access public
npm_config_cache=/tmp/kumeyuri-npm-cache npm publish --dry-run --workspace remark-kumeyuri --access public
```

Local fallback publish, only after `npm whoami` succeeds:

```bash
npm publish --workspace kumeyuri --access public --provenance
npm publish --workspace rehype-kumeyuri --access public --provenance
npm publish --workspace remark-kumeyuri --access public --provenance
```

## MCP Registry

Publish `kumeyuri-cli` to crates.io before submitting `server.json`.

```bash
mcp-publisher login github-oidc
mcp-publisher publish
```

`server.json` must validate against the MCP server schema before registry
submission.

## Release Evidence

After publish:

```bash
npm run release:trust
gh release list --limit 30
cargo search kumeyuri --limit 10
npm view kumeyuri version repository dist.integrity --json
npm view remark-kumeyuri version repository dist.integrity --json
npm view rehype-kumeyuri version repository dist.integrity --json
```

Close the matching GitHub issue only after the external registry, release, or
domain state proves completion.
