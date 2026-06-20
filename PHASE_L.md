# PHASE_L.md — Shader-in-Terminal & Procedural Input

**Goal:** Add a portable GPU compute backend (Vulkan, paired with the existing Metal one), a GLSL/WGSL cross-compiler, Shadertoy-style user shaders as a first-class input, and a tiny OBJ scene loader. Reframes contourtty from "ASCII video player" to "structure-renderer for any 2D or 3D source running in a terminal."

**Exit criteria → tag `v0.9`:** `--input shader.glsl` runs a user shader on Vulkan (Linux/Windows) or Metal (macOS), routes its output through the full structure pipeline, and renders at ≥ 30 fps on 720p truecolor; `--input scene.obj` rotates a small OBJ with depth+normal aware glyph choice; `--graph file.yaml` is a working power-user surface.

---

## Architecture decisions locked in this phase

- **Vulkan is the second backend, not the first.** Metal stays primary on Darwin; Vulkan provides Linux/Windows portability. wgpu was considered (smaller API, one backend abstraction) but adds a Rust toolchain dependency at build time. Pick Vulkan unless a future task explicitly chooses wgpu.
- **glslang as the cross-compiler.** GLSL → SPIR-V via glslang, then SPIRV-Cross to MSL on Darwin. Both header-rich C++; vendored as static libs.
- **Shader input is just another `MediaSource`.** Same interface as video/camera/scene: implements `pull(frame)` and reports timestamps. The rest of the graph doesn't care.
- **OBJ rendering is software-rendered into a G-buffer**, not OpenGL. A tiny CPU rasterizer (or Vulkan compute) writes albedo, depth, and normals into `LuminanceField`-sized buffers consumed by structure Passes. Keeps the codebase free of OpenGL/X11/EGL dependencies.

## §VulkanBackend — portable GPU compute

New `src/gpu_vulkan/` directory:
- `instance.cpp` — headless Vulkan instance with `VK_LAYER_KHRONOS_validation` (debug only); no surface, no swapchain.
- `device.cpp` — physical device pick, compute queue, fenced submissions.
- `kernels/sobel.comp.glsl`, `dog.comp.glsl`, `cell_average.comp.glsl`, `shape_match.comp.glsl` — initial set, mirrors the Metal kernels in `gpu_sobel_metal.mm`.
- `gpu_dispatch.cpp` — Pass-side adapter: takes the same inputs Metal does and produces the same outputs.

CMake: `find_package(Vulkan)`; require `VK_VERSION_1_3`. Pre-build the SPIR-V (glslangValidator at configure time) and embed via `xxd -i` so users don't need shader compilers at runtime.

- **DoD:** on Linux, `--gpu --mode structure --dog-sigma 0.5,1.4` runs end-to-end on Vulkan; output matches the macOS Metal reference within tolerance recorded in BENCHMARKS.md.

## §ShaderInput — user shaders as a media source

New `src/sources/shader_source.{hpp,cpp}`:
- Accepts `.glsl` (fragment-style with Shadertoy-like main `void mainImage(out vec4 fragColor, in vec2 fragCoord)`) or `.wgsl`.
- Wraps the user shader's body in a thin compute shell that writes to an RGBA32F output image of the working frame size.
- Provides uniforms: `iResolution (vec3)`, `iTime (float)`, `iTimeDelta (float)`, `iFrame (int)`, `iMouse (vec4)`, `iChannel0..3` (samplers; `iChannel0` defaults to the current video/camera frame for hybrid pipelines).
- Hot-reload: watch the shader file via `inotify`/`kqueue`; on change, recompile and atomic-swap the pipeline.

New `src/shader_compile.{hpp,cpp}`:
- Wraps glslang + SPIRV-Cross.
- On Darwin: SPIR-V → MSL; pipeline state object created via the existing Metal backend.
- On Linux/Windows: SPIR-V → Vulkan compute pipeline directly.

- **DoD:** a 50-line Shadertoy paste from `https://www.shadertoy.com/view/<X>` runs without edits in `--input shader.glsl`; hot-reload triggers without restart.

## §SceneInput — OBJ loader + tiny rasterizer

New `src/sources/scene_source.{hpp,cpp}`:
- Minimal OBJ + MTL parser (positions, normals, faces, texture coords; ignore advanced material features).
- Software G-buffer rasterizer:
  - Vertex shader: model-view-proj × position; output clip-space + interpolated normal + interpolated texcoord.
  - Tile-based rasterizer; per-pixel barycentric; writes `albedo`, `depth (linear)`, `normal (3×float)`, `screen_uv` into separate buffers.
- Or implement as a Vulkan compute pipeline (no graphics pipeline) — depth + normal computed in compute by software rasterization. Pick whichever is simpler.

`--input scene.obj` rotates around the model with a configurable camera (`--scene-camera azimuth,elev,radius`) at a fixed fps.

- **DoD:** rendering Suzanne (Blender's monkey) at 320×120 cells at ≥ 30 fps; depth and normals available downstream.

## §NormalGlyphs — depth/normal-aware glyph selection

New Pass `normal-orient`:
- For each cell, sample the normal buffer's average and convert to screen-space tangent.
- Drives the existing structure pipeline's orientation source instead of (or in addition to) the gradient field.

New Pass `depth-shade`:
- Sample the depth buffer per cell; map to a darkness shift on the luminance ramp index.
- Combined with normals, produces a clearly 3D-shaded ASCII look that doesn't depend on lighting accuracy.

`--style cell-shade` becomes a preset that activates Kuwahara + normal-orient + depth-shade + crosshatch (Phase K's pieces) when the input is a scene.

- **DoD:** rotated cube/Suzanne shows hatching that follows surface curvature, not 2D screen gradients.

## §GraphYaml — power-user surface

`--graph file.yaml` loads a Pass list and wiring:

```yaml
passes:
  - id: kuwahara
    backend: gpu
  - id: luminance
  - id: dog
    params: { sigma1: 0.6, sigma2: 1.8 }
  - id: sobel
  - id: etf
    params: { iters: 4 }
  - id: cell-shape
  - id: shape-match
    params: { features: hog, charset: portrait-30 }
  - id: cell-average
  - id: emit
```

YAML loader uses a minimal in-tree parser (no yaml-cpp dep necessary; subset is enough). Validates pass IDs against the registered set; reports clear errors.

`--graph dump` from Phase H already serializes the resolved graph; YAML loader is the inverse.

- **DoD:** the YAML for the default `structure` pipeline reproduces v0.5 output byte-identical; documented examples in `share/contourtty/graphs/`.

## §Shaders — bundled example shaders

`share/contourtty/shaders/`:
- `noise.glsl` — Perlin / blue noise for backgrounds.
- `plasma.glsl` — the canonical demo.
- `feedback.glsl` — uses `iChannel0` = camera + previous frame for trippy webcam loops.
- `sdf_room.glsl` — short SDF raymarch; demonstrates 3D content via shader, not OBJ.

These also serve as integration tests.

- **DoD:** all bundled shaders compile clean on both backends; run the smoke harness in CI when CI is unblocked.

## §Tests
- `shader_compile_tests.cpp` — golden SPIR-V for a fixed GLSL; equality across builds.
- `vulkan_backend_tests.cpp` — headless device init, dispatch a trivial kernel, readback.
- `scene_source_tests.cpp` — OBJ parse correctness on a simple test mesh; G-buffer sanity (depth monotonicity).
- Cross-backend equivalence: Metal and Vulkan Sobel kernels produce identical output within 1-LSB tolerance on a fixed luminance field.

## §Bench
- Shader source fps for a fixed bundled shader at 720p / 1080p.
- Scene source fps at 320×120 cells, Suzanne, software vs Vulkan raster.
- Cross-backend: Metal vs Vulkan on the same machine (if available via MoltenVK) for Sobel/DoG.

## §Files
New: entire `src/gpu_vulkan/` tree; `src/shader_compile.{hpp,cpp}`; `src/sources/shader_source.{hpp,cpp}`; `src/sources/scene_source.{hpp,cpp}`; `src/normal_orient.{hpp,cpp}`; `src/depth_shade.{hpp,cpp}`; `src/graph_yaml.{hpp,cpp}`; bundled shaders & example graphs under `share/contourtty/`.
Modified: `src/media_input.cpp` (add Shader and Scene sources), `src/cli.cpp` (`--input shader.glsl|scene.obj`, `--graph`, `--scene-camera`), `CMakeLists.txt` (Vulkan + glslang + SPIRV-Cross).

## Pitfalls
- glslang + SPIRV-Cross add tens of MB; gate behind `-DCONTOURTTY_SHADERS=ON` (default on; off for `light` builds).
- Vulkan compute-only setup is mostly boilerplate; hide it in `gpu_vulkan/instance.cpp` so the rest of the codebase touches only `gpu_dispatch.cpp`.
- Don't pretend SPIR-V is portable to MSL without quirks: some Shadertoy shaders use GL extensions (e.g. `derivatives`) that need explicit enables; document the supported subset.
- Software OBJ rasterizer is fine at small cell counts but bottlenecks at high res; offer the Vulkan-compute variant.
- Don't try to feed video and shader simultaneously through one Pass — instead make `shader_source` accept `iChannel0` as an optional second `MediaSource`. Compose in the graph, not in the source.
- Validation layers in release builds bleed performance; only enable in `--log` debug builds.
