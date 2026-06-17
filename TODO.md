# kumeyuri — Implementation TODO

> One task per line. Ordered Phase 0 → Phase 6. Check off as you go. Each task maps to the north_star.md phasing.

## Phase 0 — Foundation (weeks 0–1)

- [x] Create GitHub repo `kumeyuri/kumeyuri` (or under personal handle), set default branch to `main`
- [x] Add MIT `LICENSE` file with current year and author name
- [x] Write `README.md` v0 with one-line pitch, status badge placeholder, and link to `north_star.md`
- [x] Add `.gitignore` for Rust (`target/`, `Cargo.lock` rules per crate type), Node (`node_modules/`, `dist/`), and OS (`.DS_Store`)
- [x] Add `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1)
- [x] Add `CONTRIBUTING.md` outlining branch flow, commit style (Conventional Commits), and review expectations
- [x] Add `SECURITY.md` with disclosure email
- [x] Initialise Cargo workspace `Cargo.toml` at repo root listing all member crates
- [x] Create empty crate `crates/kumeyuri-core` with `lib.rs` and basic module skeleton (`parser`, `ast`, `layout`, `animator`, `frame`)
- [x] Create empty crate `crates/kumeyuri-render-tui`
- [x] Create empty crate `crates/kumeyuri-render-svg`
- [x] Create empty crate `crates/kumeyuri-render-raster`
- [x] Create empty crate `crates/kumeyuri-render-wasm` with `wasm-bindgen` boilerplate
- [x] Create empty crate `crates/kumeyuri-cli` with `clap` subcommand skeleton (`render`, `watch`, `play`)
- [x] Add `rustfmt.toml` and `clippy.toml` with project lint rules
- [x] Add `.editorconfig` for cross-editor consistency
- [x] Set up GitHub Actions CI workflow: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test --workspace`
- [x] Add CI job for `wasm32-unknown-unknown` build to catch web-target breakage early
- [x] Add `cargo-deny` config + CI job for license / advisory / source checks
- [x] Add `cargo-machete` or `cargo udeps` job to catch unused dependencies
- [x] Add `release-please` workflow for automated changelog + version bumps
- [x] Add issue templates (bug, feature, parser-mismatch) under `.github/ISSUE_TEMPLATE/`
- [x] Add PR template requiring linked issue + visual-diff screenshots when renderer touched
- [ ] Reserve `kumeyuri` crate name on crates.io (publish a placeholder 0.0.0)
- [ ] Reserve `kumeyuri` npm name (publish a placeholder 0.0.0)
- [ ] Reserve `kumeyuri.dev` domain (Cloudflare or Namecheap)
- [ ] Reserve `@kumeyuri` handle on X / Bluesky / Mastodon
- [x] Spike: read `mermaid-js/mermaid` parser grammar; document AST shape decision in `docs/adr/0001-ast-shape.md`
- [x] Decide token strategy: hand-rolled `chumsky`/`logos` vs port of mermaid's Jison grammar; record in `docs/adr/0002-parser-choice.md`
- [x] Vendor or pin reference output corpora from `beautiful-mermaid` and `AlexanderGrooff/mermaid-ascii` into `tests/golden/` for visual parity benchmarking (respect their licenses)

## Phase 1 — Static parity (weeks 1–4)

- [x] Implement Mermaid lexer for `flowchart`/`graph` directive header (TD, LR, BT, RL)
- [x] Implement node-id and node-shape parser (`[]`, `()`, `{}`, `(())`, `>]`, `[/...\\]`, etc.)
- [x] Implement edge parser (`-->`, `---`, `-.->`, `==>`, `--text-->`, etc.)
- [x] Implement subgraph parser
- [x] Implement `classDef` and `class` styling parser
- [x] Implement comment + directive (`%%{ ... }%%`) parser — store directives in AST but ignore unknown ones (forward-compat)
- [x] Build AST struct hierarchy in `kumeyuri-core::ast`
- [x] Implement sequence-diagram lexer (`sequenceDiagram` header, `participant`, `actor`, message arrows, `Note over`, `loop`, `alt`, `opt`, `par`)
- [x] Implement state-diagram lexer (`stateDiagram-v2`, states, transitions, composite states, `[*]`, choice/fork)
- [x] Property-test all three parsers against a fuzz corpus generated from official Mermaid examples
- [x] Implement layout engine for flowchart — port a layered Sugiyama-style algorithm or wrap `layout-rs`
- [x] Implement layout engine for sequence — lane-based linear timeline
- [x] Implement layout engine for state — same engine as flowchart with composite-state recursion
- [x] Define `Frame` type: 2D grid of glyph cells + style metadata + animation keyframe markers
- [x] Implement static-frame renderer: AST → single Frame
- [x] Implement glyph palette: ASCII set + Unicode set (box-drawing, block, arrows)
- [x] Implement theming layer with 5 starter themes (default, mono, tokyo-night, github, dracula)
- [x] Implement text-output backend in `kumeyuri-core` (`Frame` → `String`)
- [x] Add CLI `kumeyuri render <file> --format text` end-to-end
- [x] Snapshot-test flowchart static output against 20 hand-picked Mermaid examples
- [x] Snapshot-test sequence static output against 15 examples
- [x] Snapshot-test state static output against 10 examples
- [x] Visual-diff CI job: render each fixture, compare against `tests/golden/`, fail on mismatch
- [x] Side-by-side comparison doc generator: produce a markdown page showing kumeyuri vs `beautiful-mermaid` vs `AlexanderGrooff/mermaid-ascii` on the same input
- [x] Resolve every static-parity regression flagged by the comparison doc before tagging `v0.1.0-static`
- [ ] Publish `v0.1.0-static` to crates.io (CLI only, text output only)

## Phase 2 — Animation engine (weeks 4–7)

- [x] Define `KeyFrame` type and `Timeline` model in `kumeyuri-core::animator`
- [x] Specify default animation per diagram type in `docs/animations.md`
- [x] Implement sequence-playback animator: emit one frame per message activation
- [x] Implement flowchart-trace animator: highlight path BFS/DFS through nodes
- [x] Implement state-transition animator: pulse current state, light up transition arrows
- [x] Define directive schema: `%%{ animate: 'trace' | 'playback' | 'transitions' | 'none', speed: f32, loop: bool, easing: 'linear'|'ease' }%%`
- [x] Parse directives into `AnimationConfig` and feed into animator
- [x] Add `kumeyuri-render-tui`: ratatui app that renders a `Timeline` frame-by-frame
- [x] Integrate `tachyonfx` for transition effects (fade, slide, glitch) between frames
- [x] Implement `kumeyuri play <file>` CLI subcommand for one-shot TUI playback
- [x] Implement `kumeyuri watch <file>` with `notify`-based filesystem watcher and in-place re-render
- [x] Add interactive TUI controls: pause/resume (space), step (arrows), restart (r), quit (q)
- [x] Add animation speed override flag `--speed` and loop flag `--loop`
- [x] Snapshot-test animation timelines: hash the keyframe sequence per fixture
- [ ] Manual QA pass: every fixture run through `kumeyuri play` for visual sanity
- [ ] Record three terminal demo GIFs (sequence, flowchart, state) using `vhs` or `asciinema-agg`
- [ ] Publish `v0.2.0-animated-tui` to crates.io

## Phase 3 — Web / embed renderers (weeks 7–10)

- [x] Implement `kumeyuri-render-svg`: emit SVG with `<g>` per frame and SMIL `<animate>` elements
- [x] Add CSS-keyframe fallback path for SVG (GitHub sanitizer test required)
- [x] CI test: pipe generated SVG through `DOMPurify` with GitHub's allowlist; fail if animation strips
- [x] Embed accessible `<title>` + `<desc>` + plain-text fallback inside every SVG
- [x] Emit paired light/dark SVG variants (`*.svg` + `*.dark.svg`) and/or single `prefers-color-scheme`-aware SVG; document `<img class="mermaid-light/dark">` swap pattern in `docs/embedding.md` (convention popularised by `@tldraw/mermaid` Astro plugin)
- [x] Implement `kumeyuri-render-raster`: composite frames to PNG via `tiny-skia` or `cosmic-text` + glyph atlas
- [x] Implement GIF encoder path (`gif` crate or `gifski` bindings)
- [x] Implement APNG encoder path (`png` crate with animation chunks)
- [x] Implement WebP encoder path (`webp` crate, animated mode)
- [x] Add CLI flags: `--format svg|gif|apng|webp|text|tui` to `kumeyuri render`
- [x] Add `--theme`, `--charset`, `--width`, `--padding`, `--font` flags
- [x] Build `kumeyuri-render-wasm` exposing `render(source, options) -> {svg, frames}` for browsers
- [x] Wrap WASM in TypeScript package `kumeyuri` (npm) with typed API
- [x] Implement `<kumeyuri-diagram>` web component (custom element) supporting `src`, `inline`, `animate`, `theme`, `speed`, `autoplay`, `controls` attributes
- [x] Add interactive controls overlay (play/pause/scrub/restart) to the web component
- [ ] Set up CDN distribution (Cloudflare R2 + Cloudflare Pages, or jsDelivr via npm)
- [x] Write `docs/embedding.md` showing GitHub README, Hugo, Docusaurus, mdBook, plain HTML usage
- [x] Snapshot-test SVG and raster outputs (image-diff via `image-compare` crate)
- [x] Cross-browser test the web component (Chrome, Safari, Firefox, mobile) via Playwright
- [x] Performance budget: WASM bundle < 500 KB gzipped; document in CI
- [ ] Publish `v0.3.0-embed` to crates.io and `kumeyuri` to npm

## Phase 4 — Public launch (weeks 10–11)

- [x] Build landing page at `kumeyuri.dev` (Vite + Astro or plain HTML) with hero animation
- [x] Add interactive playground (textarea ↔ live diagram via WASM)
- [x] Author full docs site with mdBook: install, quickstart, syntax, directives, themes, embedding, recipes
- [x] Curate `examples/` gallery with 15 polished `.mmd` files + rendered SVG/GIFs
- [x] Write five "wow" demo diagrams: HTTP request lifecycle, OAuth flow, OS scheduler state machine, microservice fan-out, sorting algorithm trace
- [x] Record a 60-second screencast showing CLI + watch mode + web embed
- [x] Author launch blog post explaining the wedge, with embedded animations
- [x] Write Hacker News submission title + first comment (technical depth, no marketing fluff)
- [x] Draft X launch thread (3 posts max) with one GIF per post
- [ ] Schedule X launch thread for Tue/Wed 9–11am PT
- [ ] Update launch comms drafts to match current supported-root matrix before posting
- [ ] Submit to `awesome-rust`, `awesome-ratatui`, `awesome-mermaid` lists via PR
- [ ] Post to r/rust, r/programming, r/commandline with the same blog post
- [ ] Tag `v1.0.0` and publish to crates.io, npm, Homebrew tap
- [x] Set up `cargo-dist` release pipeline producing prebuilt binaries for macOS (aarch64+x86_64), Linux (x86_64+aarch64+musl), Windows (x86_64)
- [ ] Create Homebrew tap repo `kumeyuri/homebrew-kumeyuri` with auto-updated formula
- [ ] Monitor GitHub Issues + HN comments for 72h post-launch; triage P0 bugs same-day

## Phase 5 — Long-tail diagram types (post-launch)

- [x] Implement class-diagram parser, layout, static + animated rendering
- [x] Implement ER-diagram parser, layout, static + animated rendering
- [x] Implement Gantt-chart parser, layout, static + animated rendering (timeline sweep animation)
- [x] Implement pie-chart parser, layout, static + animated rendering (slice growth animation)
- [x] Implement mindmap parser, layout, static + animated rendering (radial expand animation)
- [x] Implement journey diagram parser, layout, static + animated rendering
- [x] Implement gitGraph parser, layout, static + animated rendering (commit graph growth)
- [x] Implement timeline parser, layout, static + animated rendering (scroll/reveal animation)
- [x] Implement requirement diagram parser, layout, static rendering
- [x] Implement C4 diagram parser, layout, static rendering
- [ ] Ship each as a minor release (`v1.1`, `v1.2`, ...) with its own demo GIF and changelog entry

## Phase 5A — Mermaid parity correctness + coverage backlog

- [ ] Update `COVERAGE.md` whenever parser/render behavior changes; keep Mermaid docs sidebar version and unsupported-root list current
- [x] Add root-dispatch rejection tests for every unsupported Mermaid root listed in `COVERAGE.md`
- [ ] Add one parser fixture, one static golden, and one animation/static-collapse assertion for every newly supported Mermaid root before marking it Partial or Static-only
- [x] Split `COVERAGE.md` syntax claims into parser, layout, static-render, animation, config, accessibility, and snapshot-count columns
- [x] Build a Mermaid official-example fixture importer that stores source URL, Mermaid version, root type, and expected parser/render status
- [x] Add official-example parser corpus for every currently supported root, not just flowchart/sequence/state
- [x] Add negative fixtures for known Mermaid-breaking inputs: `end` labels, nested shapes, directive-like comments, malformed frontmatter, and unknown root typos
- [x] Add source-position parse-error snapshots for representative syntax failures per supported root
- [x] Add renderer parity notes for semantic-only shapes/styles so TODO/COVERAGE do not imply visual parity where boxes are still generic
- [x] Flowchart: implement visual differentiation for Mermaid classic shapes instead of rendering all nodes as generic boxes
- [x] Flowchart: add parity tests for v11 named shapes, markdown strings, multiline labels, entity escapes, edge IDs, edge animation classes, `linkStyle`, `style`, and `click`
- [x] Flowchart: implement or explicitly reject Mermaid frontmatter/init config for `layout`, `look`, `theme`, `themeVariables`, `curve`, and ELK options
- [x] Flowchart: add layout parity cases for nested subgraph direction, external edges, self-loops, back edges, long labels, disconnected clusters, and dense fan-in/fan-out
- [x] Sequence: implement parser support for `autonumber`, `activate`, `deactivate`, `+/-` activation shorthand, `create`, `destroy`, `box`, `rect`, `critical`, and `break`
- [x] Sequence: render activation bars, participant boxes/regions, destroy markers, autonumber labels, and critical/break blocks
- [x] Sequence: add parity fixtures for actor menus, links, properties, participant ordering, multi-line notes, and message arrows without labels
- [x] State: add parity fixtures for entry/exit descriptions, concurrent states, history states, notes over composite states, `choice`/`fork`/`join` rendering, and class styling
- [x] State: implement Mermaid layout/look config parity for state diagrams or document each unsupported option with rejection tests
- [x] Class: add parity fixtures for namespaces, generics, annotations, callbacks/links, CSS class styling, two-way relations, lollipop interfaces, and member classifiers
- [x] Class: render relationship markers/cardinalities closer to Mermaid instead of class-layout approximations
- [x] ER: add parity fixtures for quoted entity/relationship labels, comments, aliases, attribute comments, composite/multivalue markers, and all cardinality variants
- [x] Gantt: replace schematic timeline rendering with date-aware scale, duration/dependency semantics, excludes/weekends, today marker, axis format, and tick interval parity
- [x] Pie: add percentage/value label parity, `showData` rendering, legend ordering, zero/negative value rejection tests, and theme/config fixtures
- [x] Journey: add actor color/style parity, section ordering, score bounds validation, and Mermaid theme/config fixtures
- [ ] GitGraph: add fixtures for branch ordering, checkout/switch aliases, merge/cherry-pick options, commit tags/types, orientation, and theme/config parity
- [ ] Timeline: add fixtures for multi-event periods, empty sections, long labels, ordering, and Mermaid theme/config parity
- [ ] Mindmap: add parity for icon registration fallback, Markdown labels, all supported shapes, class styling, indentation edge cases, and deep-tree layout
- [ ] Requirement: replace class-layout rendering with requirement-specific geometry and relationship glyphs
- [ ] Requirement: add fixtures for all requirement kinds, risk values, verify methods, element types, relationships, styles, and invalid field validation
- [ ] C4: replace class-layout rendering with C4-specific boundaries, containers, deployment nodes, relationship labels, layout calls, and style updates
- [ ] C4: add fixtures for all C4 root variants, boundary nesting, `Rel_*` indexed calls, tags, legends, sprites/icons, and unsupported macro rejection
- [ ] Quadrant Chart: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] ZenUML: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Sankey: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] XY Chart: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Block Diagram: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Packet: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Kanban: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Architecture: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Radar: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Event Modeling: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Treemap: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Venn: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Ishikawa: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Wardley: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] TreeView: implement parser, layout, static renderer, animation default, docs, and snapshot coverage
- [ ] Add cross-format snapshot coverage for all supported roots: text, SVG, PNG, GIF, APNG, WebP, TUI timeline hashes, and WASM render output
- [ ] Add browser visual regression screenshots for `<kumeyuri-diagram>` controls across desktop and mobile viewport sizes
- [ ] Add fuzz/property tests for supported-root parsers with round-trip invariants over AST counts and source spans
- [ ] Add mutation tests for parsers to ensure invalid Mermaid syntax fails fast instead of silently dropping statements
- [ ] Add compatibility CI that diffs Mermaid docs root list against `COVERAGE.md` and opens/fails on missing roots
- [ ] Add `kumeyuri compat --mermaid-version` command that prints supported roots, unsupported roots, and partial/static-only caveats
- [ ] Add a coverage gate requiring snapshot-count deltas when `DiagramKind`, parser root dispatch, or render dispatch changes

## Phase 6 — Ecosystem (ongoing, post-launch)

- [x] Build Neovim plugin (lua) — `:KumeyuriPreview` opens floating TUI
- [x] Build VSCode extension — webview embedding the WASM player; auto-render `.mmd` files on save
- [x] Build Claude-Code skill / plugin rendering mermaid blocks inline in agent output
- [x] Build opencode plugin equivalent
- [ ] Author GitHub Action `kumeyuri/render-action@v1` — converts `.mmd` files to SVG/GIF on PRs
- [ ] Publish GitHub Action `kumeyuri/render-action@v1` — converts `.mmd` files to SVG/GIF on PRs
- [x] Author rehype plugin `rehype-kumeyuri` for unified/markdown pipelines
- [ ] Publish rehype plugin `rehype-kumeyuri` for unified/markdown pipelines
- [ ] Author remark plugin `remark-kumeyuri` for markdown source transformation
- [ ] Publish remark plugin `remark-kumeyuri` for markdown source transformation
- [x] Author mdBook preprocessor `mdbook-kumeyuri`
- [x] Author Hugo shortcode `{{< kumeyuri >}}`
- [x] Author Docusaurus plugin `@docusaurus/plugin-kumeyuri`
- [x] Add Astro integration `@kumeyuri/astro`
- [x] Maintain comparison page on `kumeyuri.dev/vs` benchmarking against beautiful-mermaid and mermaid-ascii on identical inputs
- [x] Track upstream Mermaid grammar changes; bump compat matrix per release in `docs/compat.md`
- [ ] Add CI/docs check to verify `docs/compat.md` and `COVERAGE.md` Mermaid versions match
- [ ] Quarterly: post X thread with one new animation demo and download/stars chart
- [ ] Open a `good-first-issue` queue and respond to first-time contributors within 48h

## Cross-cutting / continuous

- [ ] Keep visual-diff golden snapshots up to date on every renderer change
- [ ] Maintain `CHANGELOG.md` via release-please
- [ ] Maintain `docs/adr/` decision log for any non-obvious architectural choice
- [x] Run `cargo audit` weekly via Dependabot/Renovate
- [x] Keep WASM bundle size budget enforced in CI (< 500 KB gzip)
- [ ] Triage incoming GitHub Issues within 7 days
- [ ] Publish a public roadmap pinned issue and update monthly

---

## Phase 7 — WASM plugin runtime (post-launch, ~months 4–6)

- [ ] Author RFC `docs/rfcs/0001-plugin-abi.md` proposing plugin ABI semantics
- [ ] Define `kumeyuri_abi` semver scheme and capability flags in core
- [ ] Define `RenderBackend` trait stable surface (target ABI 1.0)
- [ ] Define `DiagramType` trait surface covering parser + layout hooks
- [ ] Define `ThemeTransform` trait surface for theme preprocessors
- [ ] Decide host runtime: `wasmtime` vs `wasmer` vs `wasm-bindgen-cli` — record in `docs/adr/0010-wasm-host.md`
- [ ] Implement plugin loader in `kumeyuri-core::plugins`
- [ ] Implement capability denial defaults (no fs, no net, no env)
- [ ] Implement explicit grants via `--plugin-allow=<csv>`
- [ ] Implement plugin caching at `$XDG_DATA_HOME/kumeyuri/plugins/`
- [ ] Implement `kumeyuri plugin install <name>` resolving npm + crates.io tagged with `kumeyuri-plugin`
- [ ] Implement `kumeyuri plugin list / remove / update / disable` subcommands
- [ ] Author plugin author guide `docs/plugins/authoring.md` with hello-world example
- [ ] Build reference plugin `kumeyuri-render-pdf` as the canonical example
- [ ] Build reference plugin `kumeyuri-diagram-sankey` as second canonical example
- [ ] Add plugin smoke-test CI matrix: load each official plugin, render a sample, diff
- [ ] Document ABI deprecation policy (2-year guarantee per ABI major)
- [ ] Publish `v1.1.0-plugins` minor release

## Phase 8 — Smart-layout assistant (post-launch, ~month 5)

- [ ] Implement crossing-minimisation pass (Sugiyama phase 3) in `kumeyuri-core::layout::optimise`
- [ ] Implement long-label auto-wrap with `--max-label-width`
- [ ] Implement disconnected-subgraph clusterer with padding heuristic
- [ ] Implement orphan-node detector emitting actionable stderr suggestions
- [ ] Implement direction-swap suggestion when aspect ratio extreme
- [ ] Add `kumeyuri lint <file>` subcommand producing layout report (JSON via `--json`)
- [ ] Build a `kumeyuri-ai` companion crate (separate repo, optional dep)
- [ ] Implement BYOK envvar resolution (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`)
- [ ] Implement provider abstraction supporting OpenAI, Anthropic, OpenRouter, local llama.cpp
- [ ] Implement diff-presenter that shows AI-rewritten source vs original before apply
- [ ] Add `kumeyuri layout --ai` flag wiring to companion crate via dlopen-style optional binding
- [ ] Document smart-layout heuristics + AI fallback in `docs/smart-layout.md`
- [ ] Publish `v1.2.0-smart-layout` minor release

## Phase 9 — Internationalisation deep pass (~month 6)

- [ ] Add `unicode-width` + `unicode-segmentation` dependencies and audit current width code paths
- [ ] Add `unicode-bidi` and integrate BiDi pass in label rendering
- [ ] Add CJK full-width glyph awareness throughout layout engine
- [ ] Add BiDi snapshot tests with Arabic, Hebrew, Persian samples
- [ ] Add CJK snapshot tests with Japanese, Korean, Simplified + Traditional Chinese samples
- [ ] Integrate `fluent-rs` for user-facing strings
- [ ] Extract every user-facing string into `locales/en-US.ftl`
- [ ] Add locale-detection from `$LANG` / `$LC_ALL`; `--lang` override flag
- [ ] Open community translation issue template + crowdsource via Crowdin or Fluent file PRs
- [ ] Add font-fallback chain in raster renderer using `font-kit`: Noto Sans, Noto Sans CJK, Noto Sans Arabic, Noto Color Emoji
- [ ] Add emoji rendering test corpus (skin-tone modifiers, ZWJ sequences, regional indicators)
- [ ] Document i18n behaviour in `docs/i18n.md` including known limitations
- [ ] Publish `v1.3.0-i18n` minor release

## Phase 10 — Print / PDF / slide-deck integrations (~months 7–8)

- [ ] Implement PDF renderer in `kumeyuri-render-pdf` (plugin via Phase 7 ABI) using `printpdf` or `pdf-writer`
- [ ] Implement print-friendly theme `print-mono` (no colour, high contrast, monospace ASCII fallback)
- [ ] Implement reveal.js plugin loading kumecast files inline in slides
- [ ] Implement Marp plugin embedding kumeyuri diagrams via `marp-cli` hook
- [ ] Implement Slidev component `<KumeyuriDiagram>`
- [ ] Implement Obsidian community plugin replacing built-in mermaid with kumeyuri
- [ ] Implement Logseq plugin equivalent
- [ ] Implement Quartz plugin for digital gardens
- [ ] Implement Zola shortcode for kumeyuri embeds
- [ ] Add `docs/integrations/` directory with one page per integration
- [ ] Publish `v1.4.0-deck` minor release

## Phase 11 — Long-term maintenance & governance (ongoing, year 2+)

- [ ] Write `GOVERNANCE.md` formalising maintainer ladder (triager → committer → maintainer)
- [ ] Identify and invite first three triagers from contributor history
- [ ] Move from solo-author MIT to multi-maintainer MIT with DCO sign-off enforcement
- [ ] Establish monthly transparency post template for sponsorship income/spend
- [ ] Establish quarterly roadmap review + community office hours (async GitHub Discussions thread)
- [ ] Submit to OSS-Fuzz for continuous fuzzing once parser is stable
- [ ] Apply for SLSA Level 3 build provenance attestation
- [ ] Apply for OpenSSF Best Practices Badge silver/gold
- [ ] Migrate to multi-maintainer release signing via threshold sigstore
- [ ] Decide policy on AI-generated contributions; document in `CONTRIBUTING.md`
- [ ] Annual archive of `metrics/dashboard.svg` snapshots for historical trends

---

## Cross-cutting deep dives

### Accessibility audit checklist (continuous; gate every release)

- [ ] Run `axe-core` against web player; zero violations
- [ ] Run `pa11y` against every doc-site page; zero violations
- [ ] Verify all themes meet 4.5:1 contrast ratio (automated headless render + colour sample)
- [ ] Verify `prefers-reduced-motion: reduce` produces static SVG with progress dots
- [ ] Verify keyboard-only navigation reaches every control (manual smoke test)
- [ ] Verify NVDA, VoiceOver, JAWS narration of `aria-live` region
- [ ] Verify touch targets ≥ 44×44 px on the web player
- [ ] Verify SVG `<title>` and `<desc>` populate from diagram metadata
- [ ] Verify `.vtt` caption track generated and synced to animation
- [ ] Verify `--narrate` flag emits sensible prose for each diagram type
- [ ] Verify `--alt-text` flag returns paste-ready alt strings

### Security audit checklist (continuous; gate every release)

- [ ] Continuous fuzzing of parser via `cargo-fuzz`; corpus refreshed weekly
- [ ] Audit all regex usage; confirm linear-time `regex` crate only
- [ ] Audit SVG output sanitiser; verify no `<foreignObject>`, no `<script>`, no `href=external`
- [ ] Verify `--allow-external` is opt-in and gated
- [ ] Verify input size limit enforced (default 1 MB; configurable)
- [x] Verify `cargo-deny` advisory check passes (no known CVEs)
- [x] Verify `cargo-deny` licence check passes (allowlist enforced)
- [ ] Verify SLSA provenance attestation generated per release
- [ ] Verify all release artefacts signed with sigstore
- [ ] Verify `SECURITY.md` PGP key still valid; rotate annually

### Benchmark harness build (Phase 1, maintained continuously)

- [ ] Create `benches/compare/` directory with shared input corpus
- [ ] Wire `beautiful-mermaid` invocation (Node.js subprocess)
- [ ] Wire `AlexanderGrooff/mermaid-ascii` invocation (Go binary subprocess)
- [ ] Wire `pgavlin/mermaid-ascii` invocation (Go binary subprocess)
- [ ] Wire `mermaid2term` invocation (Crystal/npm)
- [ ] Wire `mermaid-cli` invocation (headless Chrome, ground-truth SVG)
- [ ] Wire `@tldraw/mermaid` invocation (Node + headless Chromium, sketchy SVG baseline) — added after threepointone/sunilpai-dev@f4bd28a published the pattern
- [ ] Implement fidelity scorer comparing each tool's output against ground-truth SVG
- [ ] Implement timing harness via `hyperfine`
- [ ] Implement output-size measurement
- [ ] Emit results as `bench/results.json`
- [ ] Generate static comparison page `kumeyuri.dev/vs/`
- [ ] Add weekly cron via GitHub Actions to refresh results
- [ ] If kumeyuri loses on a metric, mark loss with explanation; never hide it

### MCP server build (Phase 6, drill-down)

- [ ] Choose MCP SDK: `rmcp` (Rust) or thin handwritten transport
- [ ] Implement `render_diagram` tool surface
- [ ] Implement `play_diagram` tool surface (opens TUI subprocess)
- [ ] Implement `lint_diagram` tool surface
- [ ] Implement `list_themes`, `list_diagram_types` discovery tools
- [ ] Implement stdio transport
- [ ] Implement HTTP+SSE transport with bearer-token auth
- [ ] Add `kumeyuri mcp` CLI subcommand wiring
- [ ] Register on `mcp.directory`, `lobehub.com/mcp`, `mcpservers.org`, `glama.ai/mcp`
- [ ] Author `docs/mcp.md` with Claude Code, Cursor, Continue, opencode, Goose setup snippets
- [ ] Add MCP integration smoke test (spawn server, call each tool, assert response)

### Theming system build (Phase 1 base, expanded Phase 3+)

- [ ] Define `.kumetheme.toml` schema in `crates/kumeyuri-core/src/theme.rs`
- [ ] Validate theme files with `--validate-theme <file>` CLI flag
- [ ] Ship 10 built-in themes (default, mono, tokyo-night, github, dracula, solarized-light, solarized-dark, nord, catppuccin-mocha, high-contrast)
- [ ] Optional `sketch` theme: wobbly-stroke / hand-drawn ASCII aesthetic homage to tldraw-mermaid (cosmetic, Phase 5+)
- [ ] Implement theme search across XDG paths + project dir + bundled
- [ ] Implement `kumeyuri theme list / show / new / validate`
- [ ] Implement `kumeyuri theme publish` to GitHub-Pages-hosted index at themes.kumeyuri.dev
- [ ] Implement theme hot-reload in `kumeyuri watch`
- [ ] Document theme authoring in `docs/theming.md`
- [ ] Add theme contrast-ratio CI test (4.5:1 minimum across all themes)

### `.kumecast` format build (Phase 3)

- [ ] Specify v1 JSON schema in `docs/spec/kumecast-v1.md`
- [ ] Implement encoder in `kumeyuri-core::cast`
- [ ] Implement decoder + validator
- [ ] Implement `kumeyuri export --format kumecast`
- [ ] Implement `kumeyuri convert <cast> --format svg|gif|text` for re-rendering
- [ ] Implement `kumeyuri play <cast>` in TUI
- [ ] Add gzip variant `.kumecast.gz`
- [ ] Implement web component support: `<kumeyuri-diagram src="file.kumecast">`
- [ ] Build hosted player `play.kumeyuri.dev?cast=<url>`
- [ ] Add cast-diffing CI test ensuring format determinism across kumeyuri patch versions

### Performance budget enforcement (continuous)

- [ ] Set up `criterion` benchmarks for parse, layout, render
- [ ] Set up `dhat-rs` heap profiling in dedicated CI job
- [ ] Set up `size-limit` (or equivalent) for WASM bundle gzip budget
- [ ] Set up `playwright` perf test for first-contentful-render of web player
- [ ] Add runtime FPS counter to TUI under `--debug`
- [ ] Add CI gate: fail PR if any metric regresses > 10% without `perf:` label

### Documentation expansion (Phase 4+ continuous)

- [ ] Set up hosted mdBook at `docs.kumeyuri.dev` with `mdbook-pagefind` for search
- [x] Write `docs/book/quickstart.md` (15-minute happy path)
- [x] Write `docs/book/syntax.md` covering the current supported Mermaid subset + kumeyuri directives
- [ ] Expand syntax docs toward full vanilla Mermaid parity as supported grammar grows
- [x] Write `docs/book/directives.md` cataloguing every `%%{ }%%` directive
- [x] Write `docs/animations.md` documenting default + custom animations
- [x] Write `docs/book/themes.md`
- [ ] Write `docs/book/theming.md`
- [x] Write `docs/embedding.md` and `docs/book/embedding.md` (README, Hugo, Docusaurus, mdBook, plain HTML)
- [ ] Add X card embedding docs
- [x] Write `docs/book/cli.md` reference for every flag and subcommand
- [ ] Write `docs/api.md` Rust API reference (rustdoc + curated narrative)
- [ ] Write `docs/wasm-api.md` JS/TS API reference for the web bundle
- [ ] Expand `docs/book/recipes.md` from current short cookbook to 30+ tasks
- [ ] Write `docs/migrating-from-beautiful-mermaid.md`
- [ ] Write `docs/migrating-from-mermaid-ascii.md`
- [ ] Write `docs/migrating-from-mermaid-cli.md`
- [x] Add "Edit this page" GitHub links across every doc page
- [ ] Add "Try in playground" CTA to every code block

### Launch comms execution (Phase 4)

- [ ] T-7: draft soft-tease X post + 5-second GIF; review with 2 trusted devs
- [ ] T-7: post tease on X
- [ ] T-2: DM five friendly devs requesting reviewer slot for launch day
- [ ] T-1: dry-run install on clean macOS arm64, macOS x86_64, Ubuntu, Fedora, Windows
- [ ] T-1: validate GitHub renders example SVG correctly (regression for SMIL stripping)
- [ ] T-1: schedule HN post + X thread for Tue 9:00 AM PT
- [ ] T-0: post HN "Show HN: kumeyuri — Animated ASCII diagrams from Mermaid"
- [ ] T-0: 30 min later, post X thread with 3 demo GIFs
- [ ] T-0: crosspost lobste.rs, /r/rust, /r/programming, /r/commandline, dev.to
- [ ] T-0: respond to every HN comment within first 12 hours
- [ ] T+1: write post-launch retro thread
- [ ] T+7: submit to awesome-rust, awesome-ratatui, awesome-mermaid, terminaltrove.com
- [ ] T+30: publish 30-day metrics + roadmap update blog post
- [ ] T+90: review goal "1k stars within 90 days" — if missed, diagnose honestly

### Metrics tracking pipeline (post-launch, ongoing)

- [ ] Set up a `metrics/` directory in the repo (no external service)
- [ ] Daily cron via GitHub Actions polling stars, forks, crates.io downloads, npm downloads
- [ ] Aggregate weekly into `metrics/weekly.csv`
- [ ] Generate `metrics/dashboard.svg` weekly using kumeyuri itself (dogfooding)
- [ ] Publish dashboard as a README badge + dedicated `kumeyuri.dev/metrics` page
- [ ] Quarterly review: post X update with metrics screenshot + reflections

---

## Quality gates (must pass before tagging any release)

- [ ] `cargo fmt --check` clean
- [ ] `cargo clippy --workspace -- -D warnings` clean
- [ ] `cargo test --workspace` green
- [ ] `cargo audit` clean
- [ ] `cargo deny check` clean
- [ ] `cargo llvm-cov --workspace` ≥ 80% per crate
- [ ] Snapshot tests green (text + SVG + raster + cast)
- [ ] Performance benchmarks within budget (§18 of NORTHSTAR.md)
- [ ] WASM bundle size within gzip budget
- [ ] `axe-core` + `pa11y` audits clean
- [ ] CHANGELOG.md updated via release-please
- [ ] `docs/compat.md` matrix updated for any Mermaid grammar version change
- [ ] All public Rust APIs documented with compiling doctests

---

## Open questions to resolve before each phase

- [ ] Phase 1: Sugiyama port vs `layout-rs` wrap — measure both on benchmark corpus
- [ ] Phase 2: tachyonfx integration depth — wrap or fork
- [ ] Phase 3: SMIL vs CSS-keyframe-only SVG (GitHub sanitiser behaviour decisive)
- [ ] Phase 3: GIF encoder choice — `gif` crate vs `gifski` bindings (quality vs deps)
- [ ] Phase 4: kumeyuri.dev hosting — Cloudflare Pages vs GitHub Pages vs Vercel
- [ ] Phase 5: pacing of long-tail diagram types — bundled monthly release vs one-per-release
- [ ] Phase 6: MCP SDK choice — `rmcp` maturity vs hand-rolled stdio transport
- [ ] Phase 7: WASM host — wasmtime vs wasmer; resolve via prototyping
- [ ] Phase 8: AI provider abstraction — single trait vs per-provider crate features

---

## Competitive landscape notes (2026-06-16)

- **`@tldraw/mermaid` + threepointone's Astro plugin** (commit `threepointone/sunilpai-dev@f4bd28a`, 2026-06-15): build-time Node + headless Chromium pipeline that renders mermaid fences to paired light/dark static SVGs with a hand-drawn tldraw aesthetic. Replaces fences with `<img class="mermaid-light/dark">`. **Not a threat:** static-only, browser runtime, blog-author audience. **Does not change kumeyuri's wedge** (animation-first + terminal-native + single Rust binary). Absorbed as: (1) light/dark SVG pairing convention in Phase 3, (2) tldraw row in comparison harness, (3) optional `sketch` theme later.
