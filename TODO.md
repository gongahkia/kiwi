# kumeyuri — Implementation TODO

> One task per line. Ordered Phase 0 → Phase 6. Check off as you go. Each task maps to the north_star.md phasing.

## Phase 0 — Foundation (weeks 0–1)

- [ ] Create GitHub repo `kumeyuri/kumeyuri` (or under personal handle), set default branch to `main`
- [ ] Add MIT `LICENSE` file with current year and author name
- [ ] Write `README.md` v0 with one-line pitch, status badge placeholder, and link to `north_star.md`
- [ ] Add `.gitignore` for Rust (`target/`, `Cargo.lock` rules per crate type), Node (`node_modules/`, `dist/`), and OS (`.DS_Store`)
- [ ] Add `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1)
- [ ] Add `CONTRIBUTING.md` outlining branch flow, commit style (Conventional Commits), and review expectations
- [ ] Add `SECURITY.md` with disclosure email
- [ ] Initialise Cargo workspace `Cargo.toml` at repo root listing all member crates
- [ ] Create empty crate `crates/kumeyuri-core` with `lib.rs` and basic module skeleton (`parser`, `ast`, `layout`, `animator`, `frame`)
- [ ] Create empty crate `crates/kumeyuri-render-tui`
- [ ] Create empty crate `crates/kumeyuri-render-svg`
- [ ] Create empty crate `crates/kumeyuri-render-raster`
- [ ] Create empty crate `crates/kumeyuri-render-wasm` with `wasm-bindgen` boilerplate
- [ ] Create empty crate `crates/kumeyuri-cli` with `clap` subcommand skeleton (`render`, `watch`, `play`)
- [ ] Add `rustfmt.toml` and `clippy.toml` with project lint rules
- [ ] Add `.editorconfig` for cross-editor consistency
- [ ] Set up GitHub Actions CI workflow: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test --workspace`
- [ ] Add CI job for `wasm32-unknown-unknown` build to catch web-target breakage early
- [ ] Add `cargo-deny` config + CI job for license / advisory / source checks
- [ ] Add `cargo-machete` or `cargo udeps` job to catch unused dependencies
- [ ] Add `release-please` workflow for automated changelog + version bumps
- [ ] Add issue templates (bug, feature, parser-mismatch) under `.github/ISSUE_TEMPLATE/`
- [ ] Add PR template requiring linked issue + visual-diff screenshots when renderer touched
- [ ] Reserve `kumeyuri` crate name on crates.io (publish a placeholder 0.0.0)
- [ ] Reserve `kumeyuri` npm name (publish a placeholder 0.0.0)
- [ ] Reserve `kumeyuri.dev` domain (Cloudflare or Namecheap)
- [ ] Reserve `@kumeyuri` handle on X / Bluesky / Mastodon
- [ ] Spike: read `mermaid-js/mermaid` parser grammar; document AST shape decision in `docs/adr/0001-ast-shape.md`
- [ ] Decide token strategy: hand-rolled `chumsky`/`logos` vs port of mermaid's Jison grammar; record in `docs/adr/0002-parser-choice.md`
- [ ] Vendor or pin reference output corpora from `beautiful-mermaid` and `AlexanderGrooff/mermaid-ascii` into `tests/golden/` for visual parity benchmarking (respect their licenses)

## Phase 1 — Static parity (weeks 1–4)

- [ ] Implement Mermaid lexer for `flowchart`/`graph` directive header (TD, LR, BT, RL)
- [ ] Implement node-id and node-shape parser (`[]`, `()`, `{}`, `(())`, `>]`, `[/...\\]`, etc.)
- [ ] Implement edge parser (`-->`, `---`, `-.->`, `==>`, `--text-->`, etc.)
- [ ] Implement subgraph parser
- [ ] Implement `classDef` and `class` styling parser
- [ ] Implement comment + directive (`%%{ ... }%%`) parser — store directives in AST but ignore unknown ones (forward-compat)
- [ ] Build AST struct hierarchy in `kumeyuri-core::ast`
- [ ] Implement sequence-diagram lexer (`sequenceDiagram` header, `participant`, `actor`, message arrows, `Note over`, `loop`, `alt`, `opt`, `par`)
- [ ] Implement state-diagram lexer (`stateDiagram-v2`, states, transitions, composite states, `[*]`, choice/fork)
- [ ] Property-test all three parsers against a fuzz corpus generated from official Mermaid examples
- [ ] Implement layout engine for flowchart — port a layered Sugiyama-style algorithm or wrap `layout-rs`
- [ ] Implement layout engine for sequence — lane-based linear timeline
- [ ] Implement layout engine for state — same engine as flowchart with composite-state recursion
- [ ] Define `Frame` type: 2D grid of glyph cells + style metadata + animation keyframe markers
- [ ] Implement static-frame renderer: AST → single Frame
- [ ] Implement glyph palette: ASCII set + Unicode set (box-drawing, block, arrows)
- [ ] Implement theming layer with 5 starter themes (default, mono, tokyo-night, github, dracula)
- [ ] Implement text-output backend in `kumeyuri-core` (`Frame` → `String`)
- [ ] Add CLI `kumeyuri render <file> --format text` end-to-end
- [ ] Snapshot-test flowchart static output against 20 hand-picked Mermaid examples
- [ ] Snapshot-test sequence static output against 15 examples
- [ ] Snapshot-test state static output against 10 examples
- [ ] Visual-diff CI job: render each fixture, compare against `tests/golden/`, fail on mismatch
- [ ] Side-by-side comparison doc generator: produce a markdown page showing kumeyuri vs `beautiful-mermaid` vs `AlexanderGrooff/mermaid-ascii` on the same input
- [ ] Resolve every static-parity regression flagged by the comparison doc before tagging `v0.1.0-static`
- [ ] Publish `v0.1.0-static` to crates.io (CLI only, text output only)

## Phase 2 — Animation engine (weeks 4–7)

- [ ] Define `KeyFrame` type and `Timeline` model in `kumeyuri-core::animator`
- [ ] Specify default animation per diagram type in `docs/animations.md`
- [ ] Implement sequence-playback animator: emit one frame per message activation
- [ ] Implement flowchart-trace animator: highlight path BFS/DFS through nodes
- [ ] Implement state-transition animator: pulse current state, light up transition arrows
- [ ] Define directive schema: `%%{ animate: 'trace' | 'playback' | 'transitions' | 'none', speed: f32, loop: bool, easing: 'linear'|'ease' }%%`
- [ ] Parse directives into `AnimationConfig` and feed into animator
- [ ] Add `kumeyuri-render-tui`: ratatui app that renders a `Timeline` frame-by-frame
- [ ] Integrate `tachyonfx` for transition effects (fade, slide, glitch) between frames
- [ ] Implement `kumeyuri play <file>` CLI subcommand for one-shot TUI playback
- [ ] Implement `kumeyuri watch <file>` with `notify`-based filesystem watcher and in-place re-render
- [ ] Add interactive TUI controls: pause/resume (space), step (arrows), restart (r), quit (q)
- [ ] Add animation speed override flag `--speed` and loop flag `--loop`
- [ ] Snapshot-test animation timelines: hash the keyframe sequence per fixture
- [ ] Manual QA pass: every fixture run through `kumeyuri play` for visual sanity
- [ ] Record three terminal demo GIFs (sequence, flowchart, state) using `vhs` or `asciinema-agg`
- [ ] Publish `v0.2.0-animated-tui` to crates.io

## Phase 3 — Web / embed renderers (weeks 7–10)

- [ ] Implement `kumeyuri-render-svg`: emit SVG with `<g>` per frame and SMIL `<animate>` elements
- [ ] Add CSS-keyframe fallback path for SVG (GitHub sanitizer test required)
- [ ] CI test: pipe generated SVG through `DOMPurify` with GitHub's allowlist; fail if animation strips
- [ ] Embed accessible `<title>` + `<desc>` + plain-text fallback inside every SVG
- [ ] Implement `kumeyuri-render-raster`: composite frames to PNG via `tiny-skia` or `cosmic-text` + glyph atlas
- [ ] Implement GIF encoder path (`gif` crate or `gifski` bindings)
- [ ] Implement APNG encoder path (`png` crate with animation chunks)
- [ ] Implement WebP encoder path (`webp` crate, animated mode)
- [ ] Add CLI flags: `--format svg|gif|apng|webp|text|tui` to `kumeyuri render`
- [ ] Add `--theme`, `--charset`, `--width`, `--padding`, `--font` flags
- [ ] Build `kumeyuri-render-wasm` exposing `render(source, options) -> {svg, frames}` for browsers
- [ ] Wrap WASM in TypeScript package `kumeyuri` (npm) with typed API
- [ ] Implement `<kumeyuri-diagram>` web component (custom element) supporting `src`, `inline`, `animate`, `theme`, `speed`, `autoplay`, `controls` attributes
- [ ] Add interactive controls overlay (play/pause/scrub/restart) to the web component
- [ ] Set up CDN distribution (Cloudflare R2 + Cloudflare Pages, or jsDelivr via npm)
- [ ] Write `docs/embedding.md` showing GitHub README, Hugo, Docusaurus, mdBook, plain HTML usage
- [ ] Snapshot-test SVG and raster outputs (image-diff via `image-compare` crate)
- [ ] Cross-browser test the web component (Chrome, Safari, Firefox, mobile) via Playwright
- [ ] Performance budget: WASM bundle < 500 KB gzipped; document in CI
- [ ] Publish `v0.3.0-embed` to crates.io and `kumeyuri` to npm

## Phase 4 — Public launch (weeks 10–11)

- [ ] Build landing page at `kumeyuri.dev` (Vite + Astro or plain HTML) with hero animation
- [ ] Add interactive playground (textarea ↔ live diagram via WASM)
- [ ] Author full docs site with mdBook: install, quickstart, syntax, directives, themes, embedding, recipes
- [ ] Curate `examples/` gallery with 15 polished `.mmd` files + rendered SVG/GIFs
- [ ] Write five "wow" demo diagrams: HTTP request lifecycle, OAuth flow, OS scheduler state machine, microservice fan-out, sorting algorithm trace
- [ ] Record a 60-second screencast showing CLI + watch mode + web embed
- [ ] Author launch blog post explaining the wedge, with embedded animations
- [ ] Write Hacker News submission title + first comment (technical depth, no marketing fluff)
- [ ] Draft X launch thread (3 posts max) with one GIF per post; schedule for Tue/Wed 9–11am PT
- [ ] Submit to `awesome-rust`, `awesome-ratatui`, `awesome-mermaid` lists via PR
- [ ] Post to r/rust, r/programming, r/commandline with the same blog post
- [ ] Tag `v1.0.0` and publish to crates.io, npm, Homebrew tap
- [ ] Set up `cargo-dist` release pipeline producing prebuilt binaries for macOS (aarch64+x86_64), Linux (x86_64+aarch64+musl), Windows (x86_64)
- [ ] Create Homebrew tap repo `kumeyuri/homebrew-kumeyuri` with auto-updated formula
- [ ] Monitor GitHub Issues + HN comments for 72h post-launch; triage P0 bugs same-day

## Phase 5 — Long-tail diagram types (post-launch)

- [ ] Implement class-diagram parser, layout, static + animated rendering
- [ ] Implement ER-diagram parser, layout, static + animated rendering
- [ ] Implement Gantt-chart parser, layout, static + animated rendering (timeline sweep animation)
- [ ] Implement pie-chart parser, layout, static + animated rendering (slice growth animation)
- [ ] Implement mindmap parser, layout, static + animated rendering (radial expand animation)
- [ ] Implement journey diagram parser, layout, static + animated rendering
- [ ] Implement gitGraph parser, layout, static + animated rendering (commit graph growth)
- [ ] Implement timeline parser, layout, static + animated rendering (scroll/reveal animation)
- [ ] Implement requirement diagram parser, layout, static rendering
- [ ] Implement C4 diagram parser, layout, static rendering
- [ ] Ship each as a minor release (`v1.1`, `v1.2`, ...) with its own demo GIF and changelog entry

## Phase 6 — Ecosystem (ongoing, post-launch)

- [ ] Build Neovim plugin (lua) — `:KumeyuriPreview` opens floating TUI
- [ ] Build VSCode extension — webview embedding the WASM player; auto-render `.mmd` files on save
- [ ] Build Claude-Code skill / plugin rendering mermaid blocks inline in agent output
- [ ] Build opencode plugin equivalent
- [ ] Publish GitHub Action `kumeyuri/render-action@v1` — converts `.mmd` files to SVG/GIF on PRs
- [ ] Publish rehype plugin `rehype-kumeyuri` for unified/markdown pipelines
- [ ] Publish remark plugin `remark-kumeyuri` for markdown source transformation
- [ ] Author mdBook preprocessor `mdbook-kumeyuri`
- [ ] Author Hugo shortcode `{{< kumeyuri >}}`
- [ ] Author Docusaurus plugin `@docusaurus/plugin-kumeyuri`
- [ ] Add Astro integration `@kumeyuri/astro`
- [ ] Maintain comparison page on `kumeyuri.dev/vs` benchmarking against beautiful-mermaid and mermaid-ascii on identical inputs
- [ ] Track upstream Mermaid grammar changes; bump compat matrix per release in `docs/compat.md`
- [ ] Quarterly: post X thread with one new animation demo and download/stars chart
- [ ] Open a `good-first-issue` queue and respond to first-time contributors within 48h

## Cross-cutting / continuous

- [ ] Keep visual-diff golden snapshots up to date on every renderer change
- [ ] Maintain `CHANGELOG.md` via release-please
- [ ] Maintain `docs/adr/` decision log for any non-obvious architectural choice
- [ ] Run `cargo audit` weekly via Dependabot/Renovate
- [ ] Keep WASM bundle size budget enforced in CI (< 500 KB gzip)
- [ ] Triage incoming GitHub Issues within 7 days
- [ ] Publish a public roadmap pinned issue and update monthly
