# PHASE_H.md — Render-Graph Refactor

**Goal:** Turn `renderFrame()`'s linear if-ladder into a typed DAG of analysis Passes, so Phases I–P compose without each one tearing into the same function. No new user-visible feature; no fidelity change; all current golden-frame tests must remain byte-identical. This phase exists so every later phase has a structured place to land.

**Exit criteria:** `--mode {luminance|structure|halfblock}` + `--charset braille` all produce byte-identical CellBuffer to v0.5; `--graph dump` prints the resolved pass DAG; CPU and GPU dispatch are per-Pass capability checks rather than `if (options.gpu)` branches; new Pass can be added in one file without modifying `renderer.cpp`.

---

## Architecture decisions locked in this phase

- **DAG, not a pipeline.** Some Passes (DoG, structure shape-match) only run conditionally on flags or earlier results; some produce GPU-side buffers that downstream Passes may consume directly without a readback. A DAG with topological scheduling lets us model this cleanly.
- **Static graph, dynamic data.** The graph is resolved once at startup (and on resize / config change), not per frame. Per-frame cost stays a tight loop over an ordered Pass array.
- **CPU and GPU are siblings, not parents.** A Pass declares which backend(s) it supports; the scheduler picks one per resolved graph based on `--gpu`/capability, not per call.
- **No breaking CLI changes.** Every existing `--flag` keeps its meaning; the graph is implicit unless `--pipeline` or `--graph` is set.

## §Types — the core data model

```cpp
namespace contourtty {

enum class BufferKind {
  RgbFrame, LuminanceField, GradientField, EdgeField,
  CellGlyphs, CellColors, CellShapeVectors, OpticalFlow, Custom,
};

struct BufferDesc {
  BufferKind kind;
  int width = 0, height = 0;
  // optional sub-cell sample factor, etc.
};

struct PassPort {
  std::string name;
  BufferDesc desc;
};

enum class Backend { Cpu, Metal, Vulkan, Auto };

struct Pass {
  std::string id;                                 // unique, e.g. "sobel", "dog", "shape-match"
  std::vector<PassPort> inputs;
  std::vector<PassPort> outputs;
  std::vector<Backend>  supports;                 // ordered, most-preferred first
  std::function<void(PassContext&)> run;          // bound at graph build time
};

struct Graph {
  std::vector<Pass> ordered;                      // topo-sorted, ready to execute
};

}  // namespace contourtty
```

Each Pass reads only declared inputs and writes only declared outputs. `PassContext` exposes the resolved input buffers, the backend the scheduler chose, the `CliOptions` snapshot, and a per-frame allocator.

## §Migration — the existing pipeline becomes Passes

Lift each block of today's `renderFrame()` into a Pass without changing its math:

| Pass id        | Owns                                          | From file                |
|----------------|-----------------------------------------------|--------------------------|
| `decode`       | `Frame` (already pushed by decoder)           | n/a                      |
| `luminance`    | `makeLuminanceField`                          | `luminance.cpp`          |
| `contrast`     | `applyStructureContrast`                      | `structure_edges.cpp`    |
| `dog`          | `differenceOfGaussians`                       | `structure_edges.cpp`    |
| `sobel`        | `computeSobelGradients`                       | `structure_edges.cpp`    |
| `edge-field`   | `gradientMagnitudeField`                      | `structure_edges.cpp`    |
| `cell-average` | `averageRegion` over cells                    | `frame_sampling.cpp`     |
| `cell-shape`   | `sampleCellRegion` + `shapeVectorForCell`     | `structure_sampling.cpp` |
| `shape-match`  | `matchGlyphShape`                             | `glyph_shape.cpp`        |
| `ramp-pick`    | `glyphForLuminance`                           | `glyph_ramp.cpp`         |
| `halfblock`    | `renderHalfBlockFrame`                        | `halfblock_renderer.cpp` |
| `braille`      | `renderBrailleFrame`                          | `braille_renderer.cpp`   |
| `emit`         | diff emitter / writer                         | `diff_emitter.cpp`       |

GPU equivalents (`gpu-sobel`, `gpu-dog`, `gpu-cell-average`, `gpu-shape-match`) appear as separate Passes with the same input/output contracts; the scheduler swaps them in.

- **DoD:** every existing mode resolves to a graph; the resolved graph for `--mode luminance` is `decode → luminance → ramp-pick → cell-average → emit`; for `--mode structure --gpu --dog-sigma 0.5,1.4` it is `decode → luminance → contrast → gpu-dog → gpu-sobel → edge-field → cell-shape → shape-match → cell-average → emit`; output is byte-identical to v0.5 on all golden frames.

## §Scheduler — backend selection per Pass

```
for pass in graph.ordered:
    preferred = pass.supports.front()
    if cli.gpu and preferred in {Metal, Vulkan} and caps_allow(preferred):
        bind_backend(pass, preferred)
    else:
        bind_backend(pass, Cpu)
```

Capability check is real on macOS (Metal device present, MTL feature set) and Linux/Windows (Vulkan instance + compute queue family); both gated behind `--gpu` and `caps_allow()` actually trying to open the device once at startup. Failure falls back to CPU silently; logged.

- **DoD:** `--gpu` on a machine without Metal/Vulkan logs the fallback once and runs CPU; per-Pass dispatch decision is recorded with `--graph dump`.

## §Composition — config and `--graph`

- `~/.config/contourtty/config` gains a `pipeline=` key naming a preset: `luminance`, `structure`, `painterly` (Phase K), `crosshatch` (Phase K), `stipple` (Phase K), `shader` (Phase L).
- `--pipeline NAME` overrides config.
- Power-user surface (Phase L5 will extend this): `--graph file.yaml` lists Passes and wiring explicitly. Phase H just defines the schema; the YAML loader can be a stub returning "not yet supported" until L.
- Default behavior when no `--pipeline`/`--graph` is given: derive a graph from the current flags exactly as v0.5 does. Back-compat is non-negotiable.

- **DoD:** changing `pipeline=structure` in config produces the same result as `--mode structure` on the CLI.

## §Dump — `--graph dump`

Emit the resolved DAG to stderr (or `--log`) and exit zero:

```
decode  -> RgbFrame[1920x1080]
luminance(cpu)  RgbFrame -> LuminanceField[480x270]
contrast(cpu)   LuminanceField -> LuminanceField
gpu-dog(metal)  LuminanceField -> LuminanceField
gpu-sobel(metal) LuminanceField -> GradientField
edge-field(cpu) GradientField -> EdgeField
cell-shape(cpu) EdgeField -> CellShapeVectors[160x45]
shape-match(cpu) CellShapeVectors -> CellGlyphs
cell-average(metal) RgbFrame -> CellColors
emit(cpu)       CellGlyphs, CellColors -> stdout
```

Cheap to implement, invaluable for support and for the README's "How structure mode works" diagram.

- **DoD:** dump output is deterministic per config; covered by a golden test.

## §Tests

- Every existing golden-frame test stays green, byte-identical.
- New: `tests/render_graph_tests.cpp` covering topological sort, cycle detection, missing-input detection, backend fallback, dump format.
- Add a no-op Pass + a single test that registers/uses it from outside `renderer.cpp` — that proves the extension point Phase I+ depend on.
- **DoD:** total test count grows; no test removed; full suite still completes under 10 s on the CI runner.

## §Files

New:
- `src/render_graph.hpp`, `src/render_graph.cpp` (types, builder, scheduler, dump)
- `src/pass.hpp` (Pass + PassContext)
- `tests/render_graph_tests.cpp`

Refactored (lift code into Passes, keep the algorithms exactly):
- `src/renderer.cpp` shrinks to "build graph, run graph"
- `src/structure_edges.cpp`, `src/structure_sampling.cpp`, `src/glyph_shape.cpp`, `src/glyph_ramp.cpp`, `src/luminance.cpp` each expose a `registerPasses(Registry&)` entry

Unchanged callers: `src/main.cpp`, `src/player.cpp`, `src/cli.cpp` (except for the new `--pipeline`/`--graph dump` flags).

## Pitfalls
- Refactoring and changing math at once → impossible to bisect regressions. Keep math byte-identical in H; new math waits for I.
- Allocating per Pass per frame → loses the cache locality the current code accidentally has. Use a per-frame arena allocator; reuse buffers across Passes when descriptors match.
- Backend selection at Pass-call time → branchy. Bind once at graph build.
- Graph mutation on every resize → wasted CPU. Resize only changes buffer descriptors, not the Pass list; rebuild only when flags or font change.
- Treating GPU readback as free → it isn't. Mark Passes that can produce a GPU-resident output that the next Pass also consumes on GPU; only read back at the boundary (typically before `emit`).
