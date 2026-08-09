# Kiwi roadmap

Kiwi is renderer-first: each milestone should preserve the terminal-model/renderer boundary while adding measured capability.

## M0 — complete: renderer laboratory

LuaJIT + wgpu-native, deterministic synthetic terminal data, FreeType bitmap atlas, damage tracking, semantic render passes, diagnostics, and reproducible benchmarks.

## M1 — complete: real terminal kernel

PTY, shell lifecycle, deliberately scoped VT parser/state, resize propagation, bounded scrollback, terminfo, keyboard input, diagnostics, conformance fixtures, and deterministic replay are implemented and validated against an interactive shell and `top`. M1 does not claim full xterm compatibility.

## M2 — serious text

HarfBuzz shaping, Unicode, fallback, combining/wide characters, emoji strategy, Nerd Font validation, and HiDPI/text-quality work.

## M3 — rendering architecture expansion

Stronger render graph, selection/decorations, richer semantic metadata, improved scheduling, and graphics primitives.

## M4 — programmable rendering

Lua extension API, WGSL hot reload, semantic shader inputs, shader diagnostics, and execution budgets.

## M5 — experimental text backends

Bitmap-atlas baseline, MSDF experiment, Slug/vector experiment, and reproducible comparative benchmark suite.

## M6 — daily-driver terminal features

Clipboard, URLs, search, shell integration, configuration, IME, stronger scrollback, and packaging.

## M7 — terminal graphics protocols

Kitty graphics first; Sixel/iTerm2 only if justified by measured product value.

## M8 — launch and observability polish

Profiler/HUD, benchmark reports, demo gallery, packaging, and an architecture article.
