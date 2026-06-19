# Rust API

This page is the curated Rust API map. For exact type signatures, generate
rustdoc from the current checkout:

```sh
cargo doc --workspace --no-deps
```

## Crate map

| Crate | Purpose |
| --- | --- |
| `kumeyuri-core` | AST, parser, layout, animation timeline, frame model, text output, themes, plugin ABI |
| `kumeyuri-render-svg` | SVG rendering from `Frame` or `Timeline` |
| `kumeyuri-render-raster` | PNG/GIF/APNG/WebP rendering from `Frame` or `Timeline` |
| `kumeyuri-render-tui` | Ratatui widget renderer for frames |
| `kumeyuri-render-wasm` | wasm-bindgen browser API |
| `kumeyuri-cli` | Binary crate; use it as a process boundary, not a library API |

## Parse Mermaid

```rust
use kumeyuri_core::parser::Parser;

let diagram = Parser::parse_diagram("graph TD\nA --> B")?;
```

`Parser::parse_diagram` returns `kumeyuri_core::ast::Diagram`. The root is
`DiagramKind`, with one variant per supported Mermaid family.

Parse errors include a `ParseErrorKind` and source byte span. Treat the span as
byte offsets into the original source.

## Render static text

```rust
use kumeyuri_core::{
    frame::StaticFrameRenderer,
    parser::Parser,
    text::TextOutputBackend,
    theme::BuiltInTheme,
};

let diagram = Parser::parse_diagram("graph TD\nA --> B")?;
let frame = StaticFrameRenderer::default()
    .with_theme(BuiltInTheme::Github.theme())
    .render_diagram(&diagram);
let text = TextOutputBackend::default().render_frame(&frame);
```

Use `TextOutputBackend::exact()` when trailing spaces and fixed frame width are
part of the artifact contract.

## Animate a diagram

```rust
use kumeyuri_core::{
    animator::{AnimationOptions, Animator},
    frame::StaticFrameRenderer,
    parser::Parser,
};

let diagram = Parser::parse_diagram("sequenceDiagram\nAlice->>Bob: hello")?;
let timeline = Animator::animate_diagram_with_options_and_renderer(
    &diagram,
    AnimationOptions::default(),
    StaticFrameRenderer::default(),
)?;
```

`Timeline` contains ordered keyframes. Each keyframe owns a `Frame` and a frame
duration.

## Render SVG

```rust
use kumeyuri_render_svg::{SvgRenderConfig, SvgRenderer};

let svg = SvgRenderer::new(SvgRenderConfig::default()).render_timeline(&timeline);
```

`SvgRenderConfig` controls cell metrics, padding, font family, foreground and
background colors, optional dark-mode colors, accessibility title/description,
and animation mode (`Smil` or `CssKeyframes`).

## Render raster output

```rust
use kumeyuri_render_raster::{RasterRenderConfig, RasterRenderer};

let renderer = RasterRenderer::new(RasterRenderConfig::default())?;
let png = renderer.render_frame(timeline.keyframes()[0].frame())?;
let gif = renderer.render_gif(&timeline)?;
let apng = renderer.render_apng(&timeline)?;
let webp = renderer.render_webp(&timeline)?;
```

`RasterRenderer::new` fails fast on invalid config such as zero scale.

## Theme selection

```rust
use kumeyuri_core::theme::BuiltInTheme;

let theme = BuiltInTheme::Github.theme();
```

Built-in theme names are `default`, `mono`, `tokyo-night`, `github`, `dracula`,
and `print-mono`.

## Plugin ABI

`kumeyuri_core::abi` exposes the plugin contract:

| API | Purpose |
| --- | --- |
| `KUMEYURI_ABI_VERSION` | Host ABI version |
| `Capability` / `CapabilitySet` | Runtime capability gating |
| `RenderBackend` | External renderer backend trait |
| `DiagramType` | External diagram parser/layout trait |
| `ThemeTransform` | Theme transformation trait |

Plugin loading and cache helpers live in `kumeyuri_core::plugins`.

## Stability notes

- AST structs are public so parsers, renderers, tests, and plugins can share
  typed data. They are still expected to change before a stable 1.0 API.
- Prefer `Parser`, `Animator`, `StaticFrameRenderer`, `TextOutputBackend`,
  `SvgRenderer`, and `RasterRenderer` for application code.
- Use the CLI when you need a stable process boundary across language runtimes.
