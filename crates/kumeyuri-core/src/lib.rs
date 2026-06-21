//! Core parser, layout, animation, frame, plugin, and theme APIs.
//!
//! This crate owns Mermaid-compatible syntax parsing, terminal-frame layout,
//! animation timelines, `.kumecast` serialization, and extension surfaces used
//! by the CLI and renderer crates.

/// Plugin ABI types and capability negotiation.
pub mod abi;
/// Timeline builders and animation configuration.
pub mod animator;
/// Parsed Mermaid AST structures.
pub mod ast;
/// `.kumecast` serialization and validation.
pub mod cast;
/// Cell-grid frame primitives and glyph palettes.
pub mod frame;
/// Diagram layout engines and positioned geometry.
pub mod layout;
/// Mermaid parser entry points and parse errors.
pub mod parser;
/// WASM plugin manifests, loading, cache paths, and runtime policy.
pub mod plugins;
/// Plain-text frame output.
pub mod text;
/// Built-in themes and `.kumetheme.toml` support.
pub mod theme;
/// Unicode width, wrapping, truncation, and BiDi helpers.
pub mod unicode;
