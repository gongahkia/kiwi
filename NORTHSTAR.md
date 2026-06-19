# kumeyuri — North Star

> Transpile vanilla Mermaid syntax into beautiful, dynamic ASCII/Unicode diagrams — static or animated — that render anywhere: terminal, markdown, HTML, GitHub README, X post.

---

## 1. One-line pitch
**kumeyuri** turns any Mermaid diagram into a polished animated ASCII/Unicode artefact you can drop into a terminal, a README, a webpage, or a tweet — with zero changes to your existing `.mmd` files.

## 2. Why this exists (honest read of the landscape)

The Mermaid→ASCII space is crowded but stagnant:

| Project | Stars | Output | Animation |
|---|---|---|---|
| `lukilabs/beautiful-mermaid` | 10.4k | SVG + static ASCII, 15 themes, 6 types | ❌ |
| `AlexanderGrooff/mermaid-ascii` | 1.4k | Static ASCII/Unicode (Go CLI) | ❌ |
| `pgavlin/mermaid-ascii` | — | Static, 22 types | ❌ |
| `watzon/mermaid2term` | — | Static (Crystal/npm) | ❌ |
| `decisiongraph/graphs-tui` | — | Rust TUI, Mermaid+D2 static | ❌ |
| `Sixeight/ma` | — | Static, CLI | ❌ |
| `mermaid-ascii-diagrams` (PyPI) | — | Static | ❌ |

**Open wedge:** no tool animates. The HN discussion of `mermaid-ascii` (418↑, 66 comments, Jan 2026) had one commenter dismiss animation in ASCII as nonsensical — that is exactly the door. Animated sequence playback, flowchart execution traces, and state-machine transitions in pure text/SVG are unclaimed.

**Differentiation we will defend:**
1. **Animation-first** — every supported diagram type ships with a polished default animation.
2. **Multi-format output from one core** — single Rust engine emits TUI live, animated SVG, GIF, WebP/APNG, and a WASM-driven JS player.
3. **Zero-friction adoption** — vanilla Mermaid syntax works unchanged; `%%{ }%%` directive comments unlock advanced control without breaking other Mermaid renderers.
4. **Best-in-class static parity** — static output must visibly match or beat `beautiful-mermaid` and `AlexanderGrooff/mermaid-ascii` glyph-for-glyph before we claim a v1.

## 3. Target users

- **Open-source maintainers** embedding diagrams in READMEs that need to render on GitHub without a build step.
- **Devs documenting in terminal-first workflows** (vim, emacs, tmux, SSH, Claude Code, opencode, Aider).
- **Bloggers / tech-twitter creators** who want shareable animated explainer diagrams without Excalidraw/Figma overhead.
- **Educators** explaining state machines, sequence flows, algorithms with replayable diagrams.

## 4. North-star user experience

```bash
# Render an animated SVG and drop it in your README
kumeyuri render flow.mmd --format svg --animate trace -o flow.svg

# Live-preview in terminal, recompile on save
kumeyuri watch flow.mmd

# Export a GIF for an X post
kumeyuri render seq.mmd --format gif --speed 1.25 -o seq.gif

# Plain static for a code-block fallback
kumeyuri render flow.mmd --format text --charset unicode
```

```html
<!-- Drop-in webpage embed (WASM player) -->
<script type="module" src="https://cdn.kumeyuri.dev/player.js"></script>
<kumeyuri-diagram src="flow.mmd" animate="trace" theme="tokyo-night"></kumeyuri-diagram>
```

```markdown
<!-- GitHub README — animated SVG just works -->
![flow](./diagrams/flow.svg)
```

## 5. Architecture (single-source, multi-renderer)

```
              Mermaid source (.mmd) + optional %%{ }%% directives
                                  │
                                  ▼
                  ┌──────────────────────────────┐
                  │  kumeyuri-core  (Rust crate) │
                  │  ─ parser  → AST             │
                  │  ─ layout  → frame sequence  │
                  │  ─ animator → keyframes      │
                  └──────────────┬───────────────┘
                                 │ frame stream (text grid + meta)
        ┌──────────────┬─────────┴──────────┬──────────────┬────────────────┐
        ▼              ▼                    ▼              ▼                ▼
    ratatui TUI     animated SVG          GIF / APNG    WASM JS player    static text
    (live preview)  (README-safe)         (universal)   (interactive)     (fallback)
```

**Core invariant:** every renderer consumes the same frame stream. Adding a backend never requires touching the parser or layout engine.

**Crate layout (planned):**
- `kumeyuri-core` — parser, layout, animator, frame model. No I/O.
- `kumeyuri-render-tui` — ratatui + tachyonfx backend.
- `kumeyuri-render-svg` — animated SVG (SMIL + CSS keyframes).
- `kumeyuri-render-raster` — GIF / WebP / APNG via `image` + `gifski`-style encoder.
- `kumeyuri-render-wasm` — `wasm-bindgen` browser player + web component.
- `kumeyuri-cli` — binary that wires renderers to flags.

## 6. Scope phasing

### Phase 0 — Foundation (weeks 0–1)
Repo scaffold, CI, license, contributor docs, Mermaid parser spike, decision log on AST shape.

### Phase 1 — Static parity (weeks 1–4)
Match `beautiful-mermaid` + `AlexanderGrooff/mermaid-ascii` on **flowchart, sequence, state** static output. No animation yet. Side-by-side visual diffs in CI against reference outputs.

### Phase 2 — Animation engine (weeks 4–7)
Frame model, animator, ratatui+tachyonfx TUI renderer. Default animations: sequence playback, flowchart trace, state transitions. Live-reload (`kumeyuri watch`).

### Phase 3 — Web/embed renderers (weeks 7–10)
Animated SVG + GIF + WebP/APNG exporters. WASM player + `<kumeyuri-diagram>` web component. CDN distribution.

### Phase 4 — Public launch (week 10–11)
Landing page (kumeyuri.dev), interactive playground, polished docs, demo gallery, 5 "wow" example animations. Submit to HN, post on X with three killer GIF demos.

### Phase 5 — Long-tail diagram types (post-launch)
Class, ER, Gantt, pie, mindmap, journey, gitGraph, timeline. One per release, each with a default animation.

### Phase 6 — Ecosystem (post-launch, ongoing)
Vim/Neovim plugin, VSCode extension, Claude-Code / opencode plugins, GitHub Action (`uses: kumeyuri/render-action@v1`), rehype/remark plugins, mdBook/Hugo/Docusaurus integrations.

## 7. Success metrics (12 months post-launch)

- **1k GitHub stars** within 90 days of launch — proves the wedge.
- **Top-3 HN post** on launch day.
- **10k+ npm/crates downloads/month** by month 6 (via CLI + WASM player).
- **Inclusion in ≥ 3 high-traffic OSS READMEs** as a diagram source (proves the embed story).
- **At least one viral X thread** with > 200k impressions on a kumeyuri-generated GIF.

## 8. Non-goals (v1 explicit)

- Not a Mermaid replacement language — we consume vanilla Mermaid forever.
- Not a general TUI graphics framework.
- Not an editor / IDE — playground is read-only-by-paste.
- Not a hosted service with auth/accounts — purely client-side or CLI.
- No telemetry. No tracking. No analytics call-home.

## 9. Risks & honest mitigations

| Risk | Mitigation |
|---|---|
| `beautiful-mermaid` adds animation before we ship | Compress Phase 1–3 to ~10 weeks; soft-launch tease on X at end of Phase 2 to plant the flag. |
| Animation in ASCII reads as gimmick | Lead every demo with sequence-playback and flowchart-trace, the two cases that are obviously useful, not decorative. |
| Mermaid parser drift (upstream changes syntax) | Track upstream `mermaid-js/mermaid` parser; lock to grammar version; integration test against their fixture corpus. |
| Solo-builder burnout from broad scope | Phasing above is enforced — no Phase 5 type ships before Phase 4 launch. |
| Accessibility complaints (HN raised this) | Ship `aria-label` + textual fallback inside every animated SVG; static-text export is the a11y path. |
| GitHub strips SMIL/CSS animation in SVG | Pre-validate against GitHub's sanitizer in CI; fall back to APNG/GIF guidance in docs. |

## 10. Stack decisions (locked)

- **Language:** Rust (core, renderers, CLI). WASM via `wasm-bindgen` for browser.
- **TUI:** `ratatui` + `tachyonfx` (50+ animation effects, mature in 2026).
- **License:** MIT.
- **CI:** GitHub Actions — fmt, clippy, test, visual-diff snapshot tests, WASM build, release-please.
- **Distribution:** crates.io (lib), `cargo install kumeyuri` (CLI), Homebrew tap, prebuilt binaries via cargo-dist, npm package wrapping WASM player, CDN (Cloudflare R2 or jsDelivr) for `<kumeyuri-diagram>`.
- **Docs:** mdBook + a Vite landing page at kumeyuri.dev.

## 11. Naming & identity

- **Name:** kumeyuri
- **Tagline:** *Mermaid, animated. Anywhere text renders.*
- **Mascot / brand direction:** TBD in Phase 4 (could lean into lily/yuri visual motif for SVG watermark).

---

## 12. Accessibility commitment (WCAG 2.2 AA, all outputs)

A11y is not an afterthought; it is the long-term moat against the HN "ASCII can't be accessible" critique. Target: WCAG 2.2 AA across every rendered surface.

**Static text output:**
- Always include a leading caption line `# kumeyuri: <diagram-type> — <node-count> nodes, <edge-count> edges`.
- Provide a `--narrate` flag emitting a prose description below the diagram (useful for screen readers consuming markdown).
- Avoid colour-only encoding; differentiate edges via dash/dot/double-line glyphs in addition to colour.

**Animated SVG:**
- `<title>` and `<desc>` populated from diagram metadata.
- Embed `<aria-live="polite">` region narrating each animation step.
- Respect `prefers-reduced-motion: reduce` — render static SVG with progress dot timeline instead of animation.
- All interactive regions reachable via Tab; visible focus rings (`:focus-visible` 2px outline).
- Minimum contrast ratio 4.5:1 against background per WCAG 2.2 AA across all themes.
- High-contrast theme (`--theme high-contrast`) always available.

**Raster (GIF/APNG/WebP):**
- Companion `.txt` narration file emitted alongside each raster export by default.
- `--alt-text` flag prints a paste-ready alt-text string to stdout for markdown/HTML embedding.

**Web player / WASM:**
- Full keyboard navigation: `Space` play/pause, `←/→` step, `↑/↓` speed, `Home/End` jump, `R` restart, `F` fullscreen, `M` mute narration.
- Screen-reader-tested with NVDA, VoiceOver, JAWS during Phase 3.
- Touch targets ≥ 44×44 px (Apple HIG / WCAG 2.5.5 AAA).
- Closed-caption track (`.vtt`) generated automatically from narration.

**CI enforcement:**
- `axe-core` audit on every web-player build, zero violations to ship.
- `pa11y` audit on every doc-site page.
- Contrast ratio test per theme via headless render + colour-sampling.

## 13. Theming system

Themes are first-class artefacts, shareable as single files, hot-swappable at runtime.

**Theme file (`.kumetheme.toml`):**
```toml
name = "tokyo-night"
charset = "unicode"      # unicode | ascii | nerdfont
[colors]
background = "#1a1b26"
foreground = "#c0caf5"
accent     = "#7aa2f7"
edge       = "#9ece6a"
edge_alt   = "#f7768e"
highlight  = "#e0af68"   # active node / current message
muted      = "#414868"
[glyphs]
node_round  = ["╭", "╮", "╰", "╯", "│", "─"]
node_sharp  = ["┌", "┐", "└", "┘", "│", "─"]
arrow_right = "▶"
arrow_left  = "◀"
arrow_up    = "▲"
arrow_down  = "▼"
edge_solid  = "─"
edge_dashed = "╌"
edge_dotted = "┄"
edge_thick  = "━"
[animation]
default_easing = "ease-out"
default_speed  = 1.0
glow_radius_px = 3        # for raster/svg
trail_fade_ms  = 250
```

**Built-in themes (v1):** `default`, `mono`, `tokyo-night`, `github`, `dracula`, `solarized-light`, `solarized-dark`, `nord`, `catppuccin-mocha`, `high-contrast`.

**Custom theme discovery:** kumeyuri searches `$XDG_CONFIG_HOME/kumeyuri/themes/`, then `./.kumeyuri/themes/`, then the bundled set.

**Theme sharing:** `kumeyuri theme publish` pushes to a github-pages-hosted index at `themes.kumeyuri.dev`. Pure static — no server.

**Live theme switch:** the web component supports `theme=` attribute reactive to CSS custom-property changes (works with site-wide dark/light toggles).

## 14. `.kumecast` recording format

A shareable JSON cast of an animated diagram. One file, one URL, infinite replays.

**File spec (v1, JSON):**
```json
{
  "version": 1,
  "kind": "kumecast",
  "diagram_type": "sequence",
  "source": "sequenceDiagram\n...",
  "theme": "tokyo-night",
  "duration_ms": 4200,
  "frames": [
    { "t": 0,    "grid": "...",   "narration": "User initiates login" },
    { "t": 400,  "grid": "...",   "narration": "Server validates credentials" },
    ...
  ],
  "metadata": {
    "title": "OAuth refresh flow",
    "author": "@gongahkia",
    "created_at": "2026-06-15T12:00:00Z",
    "tags": ["auth", "oauth"]
  }
}
```

**Why a new format vs reusing asciinema:**
- asciinema `.cast` v2 is terminal-shell-output focussed; lacks structured `narration`, `diagram_type`, `theme` metadata.
- Round-trip: `.kumecast` → SVG/GIF/text via `kumeyuri convert` without re-rendering source.
- Frame grids are deterministic — diffable across kumeyuri versions, enabling visual-regression CI for community contributors.

**Player support:**
- Built into `<kumeyuri-diagram>` web component (`src="example.kumecast"`).
- Hosted player at `play.kumeyuri.dev?cast=<url>` for one-click shares.
- CLI: `kumeyuri play file.kumecast` plays in TUI.

**Compression:** gzip-encoded variant `.kumecast.gz` standard for inline embedding.

## 15. Smart-layout assistant (heuristic, AI-optional)

Bad auto-layouts are the #1 reason ASCII diagrams look amateur. Smart-layout is a deterministic heuristic pass that improves arrangement; LLM is an opt-in fallback.

**Heuristic layer (always-on, in core, no network):**
- Detect crossings; apply layer-swap to minimise edge crossings (port of Sugiyama Phase 3).
- Detect overlong labels; auto-wrap to `--max-label-width` (default 24).
- Detect disconnected subgraphs; cluster and pad whitespace between.
- Detect orphan nodes; suggest moving via stderr warning.
- Suggest direction swap (`graph TD` → `graph LR`) if aspect ratio > 3:1 or < 1:3.

**Optional LLM fallback (`kumeyuri-ai` companion crate, post-launch):**
- `kumeyuri layout --ai` ships diagram source + heuristic report to user-configured LLM endpoint.
- BYOK: reads `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `OPENROUTER_API_KEY` env vars. Never bundled credentials.
- Returns a rewritten mermaid source with reordered nodes/edges. User reviews diff before applying.
- Fully sandboxed: no network if `--ai` not passed.

**Telemetry:** none. Even with `--ai`, no kumeyuri server intermediates the request.

## 16. WASM plugin runtime (Phase 7, post-launch)

Community-supplied renderers and diagram types load as `.wasm` modules. Language-agnostic; trust-bounded via WASM sandbox.

**Plugin types:**
- **Renderer plugin** — implements `RenderBackend` interface; outputs bytes for a new format (e.g. PDF, mp4, plotly).
- **Diagram-type plugin** — implements `Parser + Layout` interfaces; adds new mermaid-style diagram support (e.g. sankey, chord, sunburst).
- **Theme transform plugin** — pre-processes themes (e.g. mono-from-image, palette-from-css).

**Distribution:** plugins live as ordinary npm or crates.io packages with a `kumeyuri-plugin` keyword. `kumeyuri plugin install <name>` resolves and caches under `$XDG_DATA_HOME/kumeyuri/plugins/`.

**Security model:** WASM sandbox + WASI capability denial by default. No filesystem, no network unless granted via `--plugin-allow=fs,net`.

**Versioning:** plugins declare `kumeyuri_abi = "1.x"`; ABI compat enforced at load time, refuse on mismatch.

## 17. Configuration & environment (CLI conventions)

**Config file precedence (lowest → highest):**
1. Bundled defaults.
2. `$XDG_CONFIG_HOME/kumeyuri/config.toml` (user).
3. `./.kumeyuri/config.toml` (project).
4. Environment variables prefixed `KUMEYURI_*`.
5. CLI flags.

**Config file (TOML):**
```toml
[defaults]
theme   = "tokyo-night"
charset = "unicode"
format  = "svg"
[render]
max_width    = 120
padding      = 1
font         = "JetBrains Mono"
font_size_px = 14
[animate]
speed = 1.0
loop  = false
respect_reduced_motion = true
[paths]
cache_dir = "~/.cache/kumeyuri"
```

**Unix-philosophy I/O:**
- Stdin: `cat flow.mmd | kumeyuri render --format svg > flow.svg`.
- Stdout default for `render`; `-o` writes to file.
- Exit codes: `0` success, `1` parse error, `2` layout error, `3` render error, `64` usage error (sysexits.h).
- All errors to stderr; never mix with stdout output.
- Machine-readable mode `--json` emits structured diagnostics for editor integrations.

**Logging:** `RUST_LOG=kumeyuri=debug` controlled via `tracing` crate. Default = WARN.

**XDG compliance:** strict on Linux, best-effort on macOS, sane fallbacks on Windows.

## 18. Performance budgets (CI-enforced)

| Metric | Budget | Enforcement |
|---|---|---|
| `kumeyuri-core` cold parse + layout (100-node flowchart) | < 50 ms | criterion benchmark, fail on > 60 ms regression |
| Single-frame text render (100 nodes) | < 5 ms | criterion |
| Animated SVG generation (50 frames) | < 200 ms | criterion |
| GIF encoding (50 frames, 800×600) | < 800 ms | criterion |
| WASM bundle (player + runtime) gzipped | < 500 KB | CI size-limit job, fail PR |
| First contentful render in `<kumeyuri-diagram>` (cold) | < 250 ms | playwright perf test |
| TUI animation frame rate | ≥ 30 fps target, ≥ 24 fps minimum | runtime fps counter in `--debug` |
| Peak heap, 1000-node diagram | < 50 MB | dhat-rs in dedicated CI job |

[Inference] Budgets are starting points; tune per measured baseline after Phase 1 lands.

## 19. Security & supply-chain

**Parser:**
- Fuzz-test parser via `cargo-fuzz` continuously; corpus seeded from Mermaid official examples.
- Submit to OSS-Fuzz once stable (post-v1.0).
- Reject inputs > 1 MB by default (configurable via `KUMEYURI_MAX_INPUT_BYTES`).
- All regexes audited for ReDoS; prefer `regex` crate (linear time guaranteed) over `fancy-regex`.

**Renderer:**
- SVG output: no JavaScript, no `<foreignObject>`, no external resource references (`<image href>` blocked) by default. `--allow-external` opt-in.
- Raster output: vetted dependencies (`image`, `gif`, `webp`), no native FFI beyond what those crates use.

**Supply chain:**
- All releases signed via `sigstore` / `cosign`.
- Provenance attestations published via GitHub Actions OIDC.
- SLSA Level 3 target by end of Phase 4.
- `cargo-deny` enforces licence allowlist (MIT/Apache-2.0/BSD/ISC/CC0/Unicode-DFS-2016 only).
- Dependabot + Renovate dual-tracked for redundancy; weekly auto-PR review.

**Disclosure:** `SECURITY.md` with PGP key + GitHub private advisories; 90-day responsible disclosure window.

## 20. Internationalisation

**Text rendering:**
- Unicode normalisation NFC on all input labels.
- Grapheme-cluster-aware width via `unicode-width` crate (avoids "smile-face = 2 cells" miscounts).
- BiDi support via `unicode-bidi` for RTL labels (Arabic, Hebrew). Diagram structure stays LTR, labels flip via BiDi algorithm.
- CJK full-width handling: 2-cell advance for CJK glyphs; layout engine honours.
- Emoji rendering: terminal-dependent; raster/SVG paths use `noto-emoji` fallback bundled via `font-kit`.

**UI/CLI strings:**
- All user-facing strings via `fluent-rs` ICU MessageFormat. English shipping language; community translations welcome.
- Locale detection via `$LANG` / `$LC_ALL` / `--lang` flag.

**Documentation:**
- English authoritative. Phase 6+ accepts community translations for landing page and getting-started docs only (full docs stay English to avoid drift).

## 21. Versioning policy

- **SemVer strict** post-`v1.0.0`.
- **Pre-1.0 phase:** breaking changes permitted on minor bumps; documented in `CHANGELOG.md`.
- **MSRV (Minimum Supported Rust Version):** N-2 stable; bumped only with minor version bump and 30-day deprecation notice.
- **Mermaid grammar compat:** matrix in `docs/compat.md` lists supported Mermaid `mermaid-js` versions per kumeyuri release. Upstream grammar changes do NOT force a major bump unless deletions occur.
- **Plugin ABI:** independently versioned (`kumeyuri_abi = "1.x"`); changes follow semver. ABI 1.x guaranteed for two years post-introduction.
- **Release cadence target:** patch as needed, minor monthly during Phase 1–4, quarterly post-launch. Major versions only when justified.

## 22. Distribution channels (detailed)

**CLI binary:**
- `cargo install kumeyuri`
- `brew install kumeyuri/tap/kumeyuri`
- `scoop install kumeyuri` (Windows)
- `nix-env -iA nixpkgs.kumeyuri` (NixOS, post-launch PR upstream)
- Prebuilt tarballs via `cargo-dist`: `darwin-aarch64`, `darwin-x86_64`, `linux-x86_64-gnu`, `linux-x86_64-musl`, `linux-aarch64-gnu`, `windows-x86_64`.
- `curl -fsSL kumeyuri.dev/install.sh | sh` one-liner.
- Docker image `ghcr.io/kumeyuri/kumeyuri:latest` (multi-arch, distroless base).

**Library:**
- crates.io: `kumeyuri-core`, `kumeyuri-render-*`, `kumeyuri-cli`.
- npm: `kumeyuri` (WASM wrapper, ESM + CJS + types), `@kumeyuri/web-component`.
- JSR: mirrored for Deno-first ecosystem.
- Pypi: `kumeyuri-py` (post-v1, thin pyo3 wrapper).

**CDN:**
- `cdn.kumeyuri.dev/v{version}/player.js` (Cloudflare R2 + cache).
- Mirrored on jsDelivr and unpkg for redundancy.

**GitHub Action:**
- `kumeyuri/render-action@v1` — renders all `.mmd` files in a repo, opens PR with updated SVGs.

## 23. Community & governance

- **License:** MIT.
- **Code of Conduct:** Contributor Covenant 2.1.
- **Discussion:** GitHub Discussions only at first; Discord considered post-launch if demand justifies (avoid platform sprawl).
- **RFC process:** non-trivial changes need a `docs/rfcs/NNNN-title.md` PR. Open RFCs reviewable for 7 days minimum.
- **Maintainership ladder:** triager → committer → maintainer, documented in `GOVERNANCE.md`. Solo maintainer at start; explicit invite to triager role after 3 substantive PRs.
- **Funding transparency:** if GitHub Sponsors funds appear, monthly transparency post listing income and how it is spent.
- **No CLA:** DCO sign-off only.

## 24. Documentation strategy

**Layered docs:**
1. `README.md` — pitch, install, 30-second example, link to docs site.
2. `kumeyuri.dev` landing — interactive playground above the fold.
3. `docs.kumeyuri.dev` (mdBook) — guides, reference, API, recipes.
4. `crates.io` rustdoc — API reference.
5. `examples/` directory — 30+ curated `.mmd` files with rendered outputs.
6. `RECIPES.md` — copy-paste solutions to common tasks.
7. `MIGRATING.md` — from each competitor (beautiful-mermaid, mermaid-ascii, mermaid-cli).

**Doc-site features:**
- Full-text search via `pagefind` (static, no server).
- Each code block has copy button + "open in playground" link.
- Live-rendered SVG diagrams inline.
- Dark/light theme toggle.

## 25. Comparison benchmark harness

Public, automated, brutally fair.

- `benches/compare/` ships identical Mermaid inputs through kumeyuri, beautiful-mermaid, AlexanderGrooff/mermaid-ascii, pgavlin/mermaid-ascii, mermaid2term.
- For each tool: capture static-render time, output size, glyph fidelity score (vs SVG ground truth), and screenshot.
- Output published as a static page on `kumeyuri.dev/vs/` updated weekly via cron.
- Methodology, raw timings, and source data linked. Anyone can reproduce locally with `make compare`.
- If kumeyuri loses on a metric, the comparison page says so plainly. Honesty is the moat.

## 26. MCP server design (Phase 6)

`kumeyuri mcp` exposes render-to-image as MCP tools for agentic CLIs.

**Exposed tools:**
- `render_diagram(source, format, theme, animate)` — returns image bytes or text.
- `play_diagram(source, theme)` — opens a live TUI window for the user; useful for Claude Code workflows.
- `lint_diagram(source)` — returns parse warnings + layout suggestions.
- `list_themes()`, `list_diagram_types()` — discovery.

**Transport:** stdio MCP transport primarily; HTTP+SSE optional via `--transport http --port 4477`.

**Discoverability:** registered on `mcp.directory`, `lobehub.com/mcp`, `mcpservers.org`, `glama.ai/mcp`. [Inference] existing mermaid MCP servers (claude-mermaid, sailor, peng-shawn/mermaid-mcp-server) all render via headless browser; kumeyuri's pure-Rust path is faster and works offline.

**Auth:** local-only by default; HTTP transport requires bearer token from `KUMEYURI_MCP_TOKEN`.

## 27. Quality bars / definition of done

**Per phase:**
- All snapshot tests green.
- Clippy clean at `-D warnings`.
- `cargo audit` clean.
- Coverage ≥ 80% per crate (measured via `cargo-llvm-cov`).
- All public APIs documented with doctests that compile.
- Performance budgets in §18 met or budget bump justified in CHANGELOG.

**Per release:**
- All "good first issue" PRs from prior cycle merged or labelled `wontfix` with reason.
- Compatibility matrix in `docs/compat.md` updated.
- Release notes drafted for laypersons, not just engineers.

## 28. Launch comms playbook

**T-7 days:**
- Soft tease on X: single 5-second GIF, no link. Plants the flag.
- DM five friendly devs for next-day feedback on dry-run launch post.

**T-1 day:**
- Final dry run of install paths on a fresh macOS VM and a fresh Linux container.
- Validate that GitHub renders the README SVG correctly.
- Schedule HN post and X thread for Tue/Wed 9:00 AM PT.

**T-0 day:**
- HN post first (`Show HN: kumeyuri — Animated ASCII diagrams from Mermaid`).
- X thread 30 minutes later with three killer GIFs.
- /r/rust, /r/programming, /r/commandline, lobste.rs, dev.to crosspost.
- Personally respond to every HN comment for first 12 hours.

**T+7 days:**
- Post-launch retro thread: stars, downloads, top feedback, what's next.
- Submit to `awesome-rust`, `awesome-ratatui`, `awesome-mermaid`, `terminaltrove.com`.

**T+30 days:**
- "30 days after launch" follow-up blog post with metrics and roadmap update.

## 29. Metrics tracking without telemetry

No call-home. Measure adoption from public signals only:
- GitHub stars, forks, watchers via `gh api`.
- crates.io download counts (daily snapshot to `metrics/` repo).
- npm download counts via `npm-stat` API.
- Homebrew analytics opt-in counts (Homebrew anonymises).
- Issue / PR throughput.
- Referrer mentions discovered via `gh search`.

Aggregated weekly into a public `metrics/dashboard.svg` (yes, generated with kumeyuri — eat own dogfood).

## 30. Stretch goals / future ideas (not committed)

- [Speculation] Print/PDF backend for academic-paper figures (`kumeyuri render --format pdf`).
- [Speculation] reveal.js / Marp / Slidev presenter plugin auto-pulling kumecasts.
- [Speculation] Real-time collaboration playground (multi-cursor mermaid editing) — likely requires server, skip unless monetisation flips.
- [Speculation] Native macOS app (`Kumeyuri.app`) wrapping the WASM player with quick-look integration.
- [Speculation] Obsidian plugin replacing built-in Mermaid render with animated output.
- [Speculation] Diagram diff tool (`kumeyuri diff a.mmd b.mmd`) showing animated transition between two versions.
- [Speculation] Voice narration via system TTS in the web player (`--narrate-tts`).
- [Speculation] LSP server for `.mmd` files providing real-time layout warnings in editors.
- [Speculation] `kumeyuri server` for self-hosted teams who want a shared gallery without paid SaaS.

Each item must pass the "does this serve the north star?" test before moving to TODO.
