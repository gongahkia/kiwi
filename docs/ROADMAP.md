# Kiwi roadmap

Kiwi is renderer-first: each milestone should preserve the terminal-model/renderer boundary while adding measured capability.

## M0 — complete: renderer laboratory

LuaJIT + wgpu-native, deterministic synthetic terminal data, FreeType bitmap atlas, damage tracking, semantic render passes, diagnostics, and reproducible benchmarks.

## M1 — complete: real terminal kernel

PTY, shell lifecycle, deliberately scoped VT parser/state, resize propagation, bounded scrollback, terminfo, keyboard input, diagnostics, conformance fixtures, and deterministic replay are implemented and validated against an interactive shell and `top`. M1 does not claim full xterm compatibility.

## M1.5 — complete: measured pipeline hardening

Layered parser/state/damage/packing/scroll benchmarks, LuaJIT profiler evidence, bounded PTY service turns, real-PTY burst/response checks, schema-versioned result metadata, and performance decision records are implemented. This milestone retains M1's terminal semantics and renderer boundary; it does not add M2 text functionality.

## M2 — complete: bounded native text foundation

Pinned Unicode 17 data and full UAX #29 EGC conformance, deterministic terminal width, grapheme/anchor/continuation cells, HarfBuzz shaping, Fontconfig fallback, glyph-ID alpha atlas rendering, diagnostics, native-text benchmarks, and bounded stress checks are implemented. M2 deliberately remains LTR-only, grayscale-atlas-only, and startup-configured; bidi, color emoji, atlas paging/eviction, runtime reflow, and text-quality expansion remain deferred.

## M2.5 — complete: performance hardening

M2.5 preserves M2 terminal/parser/text boundaries while adding schema-versioned write-path stage attribution, reproducible LuaJIT sampling/trace capture, clean same-configuration comparison, cursor-only text-invalidation tests, and a constrained direct ASCII optimization. It does not claim a general Unicode or presentation-latency improvement.

## M3 — next: rendering architecture and programmability

Stronger render graph, selection/decorations, richer semantic metadata, improved scheduling, graphics primitives, and a bounded programmable-rendering surface (Lua extension API, WGSL hot reload, semantic shader inputs, diagnostics, and execution budgets). M3 begins only after M2.5 release evidence is accepted.

## M4 — experimental text backends

Bitmap-atlas baseline, MSDF experiment, Slug/vector experiment, and reproducible comparative benchmark suite.

## M5 — daily-driver terminal features

Clipboard, URLs, search, shell integration, configuration, IME, stronger scrollback, and packaging.

## M6 — terminal graphics protocols

Kitty graphics first; Sixel/iTerm2 only if justified by measured product value.

## M7 — launch and observability polish

Profiler/HUD, benchmark reports, demo gallery, packaging, and an architecture article.
