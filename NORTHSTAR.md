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
