# Kiwi M0 architecture

Kiwi M0 is deliberately a terminal renderer laboratory. Its central boundary is `TerminalModel -> Renderer`; neither side owns the other.

```
app/main.lua
  -> terminal/synthetic.lua
  -> terminal/model.lua + terminal/damage.lua
  -> renderer/renderer.lua
       -> renderer/passes.lua
       -> font/freetype.lua + font/atlas.lua
       -> gpu/context.lua
  -> ffi/{glfw,wgpu,freetype}.lua
  -> GLFW / FreeType / wgpu-native / Vulkan
```

## Layers and dependency direction

`terminal/` contains only logical cells (`glyph`, foreground/background packed RGBA, flags) and sparse damage. It has no GPU imports. `font/atlas.lua` owns placement policy and atlas bookkeeping; `font/freetype.lua` performs the initial basic-Latin rasterization. `renderer/` converts only dirty logical cells into 40-byte `KiwiGlyphInstance` records. `gpu/` owns native handles, surface configuration, and explicit destruction. `platform/` owns GLFW window/input/drawable-size details. `ffi/` is the sole home for native declarations.

The one narrow C bridge, `native/surface.c`, is not application logic. It is compiled against the pinned wgpu header and only handles ABI-sensitive native boundaries: GLFW Wayland/X11 surface-chain construction, wgpu v29 asynchronous callback polling, and the chained WGSL source descriptor. LuaJIT FFI cannot safely receive the v29 callback signatures because they pass `WGPUStringView` by value. Terminal semantics, atlas policy, pass scheduling, buffer packing, benchmark logic, and all draw orchestration remain LuaJIT.

## Logical and GPU cells

```
LogicalCell                     KiwiGlyphInstance (40 bytes, aligned 4)
-----------                     -----------------------------------------
glyph: one ASCII byte       ->  x, y: f32 cell coordinate
fg/bg: 0xAARRGGBB           ->  u0, v0, u1, v1: f32 atlas rectangle
flags: bold/semantic/recent ->  fg, bg, flags, glyph: u32
```

The instance structure is declared once in `renderer/packing.lua`; tests assert its 40-byte size and 4-byte alignment. WGSL uses the matching storage-buffer layout. This is a deliberate M0 bitmap-atlas format, not a commitment to a future MSDF or vector backend.

## Glyph path

FreeType opens the system monospace font selected by Fontconfig (or `KIWI_FONT`), sets a pixel size, and loads codepoints 32–126 with `FT_LOAD_RENDER`. `font/atlas.lua` shelf-packs the resulting bitmaps into a fixed 1024×1024 R8 atlas and tracks per-glyph UVs, bearings, and advance. The one-time atlas upload uses `wgpuQueueWriteTexture`; glyph pixels are sampled by `renderer/terminal.wgsl` in the glyph pass. The terminal is never CPU-rasterized into one texture per frame.

## Render graph

`renderer/passes.lua` explicitly preserves this pass order:

```
surface texture
  -> terminal/background  clear + structured cell backgrounds + semantic/debug highlight
  -> terminal/glyph       atlas-sampled glyph quads from structured cell data
  -> terminal/cursor      animated outline from explicit cursor/time uniform
  -> present
```

Each pass owns a named pipeline, load policy, instance count, and `encode` method. The pass abstraction is intentionally small; later semantic passes can use the same contract without introducing a generic game-engine graph.

`F2` makes `recent` cells visually distinct and `F3` draws cell boundaries. Both consume terminal metadata in the background pass, demonstrating semantic input rather than framebuffer post-processing.

## Damage and GPU updates

Damage is a sparse logical-index set plus a lazy full-redraw flag. Adjacent marked cells coalesce into ordered ranges when consumed.

```
TerminalModel:set()
  -> Damage:mark(index)
  -> Renderer:update_model()
       -> pack each changed LogicalCell only
       -> one wgpuQueueWriteBuffer per contiguous range
       -> record cells, bytes, ranges, and full/partial state
  -> Damage:clear()
```

A typing update changes 1–4 cells plus cursor endpoints; it therefore stages substantially less data than an 8,000-cell full redraw. Row churn tends to form one range. `mark_all_dirty()` represents resize/reset/full-redraw without first inserting every index into the sparse set. Buffer capacity is the current grid size; resizing a future terminal model requires creating a matching renderer/buffer capacity before presentation.

## Frame lifecycle and resource convention

The app polls events, waits up to the next 30 Hz tick, applies the selected synthetic scenario, stages damage, updates the cursor/time uniform, encodes the three passes, submits, and presents. A zero-sized drawable skips rendering; resize reconfigures the surface; `Esc` requests close. FIFO presentation is selected to avoid an accidental uncapped loop.

GPU resources are not left to garbage collection. `Renderer:destroy()` releases texture views, textures, buffers, samplers, bind groups, layouts, shaders, and pipelines in reverse order. `Context:destroy()` unconfigures/releases the surface, then queue, device, adapter, and instance. Failed construction tears down already-created handles before rethrowing. The native bridge captures uncaught GPU errors and device loss; the app treats either as fatal, then performs the same explicit cleanup.

Diagnostics report frame and preparation CPU time, logical/dirty/uploaded cells, upload bytes/ranges, draw calls, atlas data, drawable size/scale, and adapter information. The adapter's timestamp-query capability is detected. M0 reports GPU timing as unsupported because it intentionally omits timestamp query/readback plumbing from this baseline; it does not synthesize a GPU timing value.

## Future extension points

M1 can replace `terminal/synthetic.lua` with a PTY/VT-backed producer while retaining `TerminalModel` and `Renderer`. M2 can provide a different font atlas source and richer glyph records. M3 can add decoration/selection/semantic passes. M4 can expose the pass/resource contract to Lua extensions after API constraints are established by measured use.
