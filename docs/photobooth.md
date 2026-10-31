# strok photobooth

The public photobooth is a static browser frontend for the existing C++20 SDK.
The browser captures camera frames or decodes an uploaded image, sends RGBA to
the real renderer compiled to WebAssembly, and draws its `CellBuffer` to Canvas.
There is no JavaScript replacement renderer or server processing.

The native CLI, public C++ headers, C ABI, Python/NumPy and Rust/Bevy bindings,
and recording player remain available. The booth links to the repository and
explains that it uses the same rendering engine.

## Build locally

Use Node.js 22.12 or newer, CMake 3.20 or newer, Python 3, and Emscripten
**4.0.23**. Native FFmpeg, FreeType, Metal, and Vulkan installations are not
needed for this build. Emscripten builds its own FreeType port.

Install the compiler outside the source tree, or into an ignored cache:

```sh
git clone --depth 1 --branch 4.0.23 https://github.com/emscripten-core/emsdk.git .cache/emsdk
.cache/emsdk/emsdk install 4.0.23
.cache/emsdk/emsdk activate 4.0.23
source .cache/emsdk/emsdk_env.sh
npm ci --prefix web
npm run build --prefix web
npm run dev --prefix web
```

Open `http://localhost:4173`. The server binds only to localhost. Camera access
works on localhost and deployed HTTPS origins; opening `index.html` as a local
file is not supported. For a physical phone, serve the built output over HTTPS
with a trusted certificate or deploy to Pages. Plain HTTP on a LAN address does
not qualify for camera access.

Build output is `web/dist/`; the native module is generated under
`build/web/wasm/`. When only HTML/CSS/JS changes, reuse the compiled renderer:

```sh
node web/scripts/build.mjs --skip-wasm
```

`EMSDK=/absolute/path/to/emsdk npm run build --prefix web` also works without
sourcing the SDK environment. `CMAKE_BUILD_PARALLEL_LEVEL` controls build jobs
(default two). The first build downloads the Emscripten FreeType/zlib ports;
later builds reuse the compiler cache. Use a disk-backed `TMPDIR` if the host's
temporary filesystem is too small for compiler downloads.

## Deploy on GitHub Pages

In the repository's **Settings → Pages → Build and deployment**, select
**GitHub Actions** as the source. Push the changes to `main`, or run the
**Photobooth / GitHub Pages** workflow manually.

The workflow compiles the C++ renderer, runs the WebAssembly/model tests,
exercises Chromium and WebKit, uploads screenshots, then deploys `web/dist/`.
Pull requests build and test without publishing. Native CI remains separate.

All application assets use relative URLs, including the worker, fonts and WASM.
The same output works under a project path such as
`https://gongahkia.github.io/strok/` or a custom-domain root. Browser tests serve
the build at `/strok/` to catch path regressions. `.nojekyll` is generated.
No backend, API key, Pages-specific response headers, or cross-origin isolation
configuration is needed.

## Visitor experience

- The initial generated solar-system demo demonstrates the actual C++ renderer without
  requesting a camera or downloading any photo.
- Start/stop the camera, switch front/rear cameras when available, and mirror
  the preview. Camera permission is requested only after the visitor clicks.
- Upload a local image. It stays on the device. Uploads are fitted to 4:3,
  preserving the whole image; camera previews fill the viewfinder.
- Choose structure, classic luminance, crosshatch, Braille, half blocks, or
  stipple. Pick original colors, paper, amber, phosphor green, pink/plum, or a custom color from the dropper.
- Set character density, edge sensitivity and contrast. Temporal glyph
  stabilization can be disabled. Reset the look at any time.
- Capture a single photo or a two-, three-, or four-frame strip with a 0/3/5/10-second timer.
  Further strip frames have at least a one-second gap. Click Cancel or press
  Escape during a countdown to discard the incomplete capture.
- Save a framed PNG or the Unicode character grid as `.txt`. Share the PNG on
  devices with file sharing; the Share action downloads it otherwise.
- Keep up to twelve captures in this tab. Removing/clearing entries releases
  their object URLs. Reloading clears the collection.

Camera tracks stop when the visitor stops the camera, changes to an image/demo,
switches cameras, hides the tab, or leaves the page. Reopening a hidden tab
requires starting the camera again. Rendering pauses in hidden tabs. Reduced
motion preferences make the generated demo a still image.

## Architecture and boundaries

`cmake/StrokCoreSources.cmake` is shared with the native build; core source files
are compiled directly into `strok.wasm`. `web/src/bridge.cpp` adapts the SDK to a
small exported C interface. It validates frame dimensions and produces packed
Unicode/foreground/background triples. This adapter does not change the native
versioned C ABI.

The module embeds the same Source Code Pro font used by the canvas, charset
presets and the blue-noise stipple tile. The font's SIL Open Font License is in
`web/assets/SourceCodePro-LICENSE.txt`. Braille dots and half blocks are drawn
geometrically so results do not depend on a platform's symbol fonts.

One serial C++ renderer runs inside a dedicated module Web Worker. No pthreads
or `SharedArrayBuffer` are required. One input frame can be in flight at a time;
old source/configuration results are discarded using an epoch. Configuration
changes recreate the renderer; source changes explicitly reset temporal state.
RGBA buffers transfer into the worker, and a reusable WASM allocation avoids
allocating native input memory every frame. The worker returns a packed copy of
the output cells. Canvas painting and palette choices live in the frontend.

Analysis resolution is bounded to 288×216, character grids to 144×54. Single
photo PNGs are 1200 pixels wide; photo strips are 720 pixels wide. Export
redraws the captured cells rather than upscaling a viewfinder screenshot. The
actual preview rate depends on the device, effect and density; no fixed mobile
frame rate is promised.

The browser build uses CPU rendering. Native Metal/Vulkan, terminal protocols,
FFmpeg device/URL decoding, YouTube resolution and CLI audio playback are not
part of this photobooth. Images depend on the browser's decoders; unsupported
formats show a recoverable error. Animated images are treated as still photos.
The initial site does not record video or provide accounts/cloud galleries.

## Verification

```sh
npm test --prefix web
cd web
npx playwright install --with-deps chromium webkit
npm run test:browser
```

The model tests cover option bounds, Unicode text exports, source aspect ratios
and actionable camera errors. The WebAssembly tests execute the compiled C++
effects with embedded assets, invalid inputs, temporal reset and repeated
renderer lifecycles.

Browser tests cover all six textures, palettes, density/advanced controls,
shutter/strip/cancellation, PNG and text downloads, camera switching and
track release with Chromium's fake camera, valid/invalid uploads, camera denial,
missing WASM recovery, reduced motion, WCAG AA checks, and 320/390/768-pixel
layouts. A WebKit mobile viewport also exercises rendering and capture. Tests
reject unexpected external asset requests. Screenshots go to the ignored
`web/test-results/` directory and CI artifacts.

The camera tests also check delayed permission approval after a source change;
late camera streams must be stopped rather than replacing the demo. Downloads
are checked for a valid 1200-pixel PNG and correctly sized Unicode text grids.
`WEBKIT_EXECUTABLE_PATH` can select a locally provisioned Playwright-compatible
WebKit launcher; CI uses the standard Ubuntu 24.04 Playwright installation.

These automated checks do not replace testing physical iOS/Android cameras,
native sharing sheets or temperature/battery behavior on real phones.

The shared core can be checked independently:

```sh
cmake -S . -B build/core-check -DCMAKE_BUILD_TYPE=Release \
  -DSTROK_BUILD_CLI=OFF -DSTROK_LIGHT=ON -DSTROK_TEST_INSTALLED_CONSUMERS=OFF
cmake --build build/core-check --parallel --target \
  strok_core_consumer renderer_lifecycle_tests renderer_isolation_tests \
  renderer_config_tests c_api_lifecycle_tests reconstruction_baseline_tests \
  temporal_stability_tests
ctest --test-dir build/core-check --output-on-failure \
  -R '^(core_consumer|renderer_lifecycle|renderer_isolation|renderer_config|c_api_lifecycle|reconstruction_baseline|temporal_stability)$'
```

## Interface

The booth uses a compact control column beside the character preview on desktop,
with Blocks, original colors and maximum character density (144 columns) as the defaults. The block-character Strok
wordmark scales to the control column width. Bracketed texture selections and
monospaced labels carry the character art into the interface. Color palettes
remain available without changing the surrounding interface. On phones, camera
controls appear before the viewfinder, with texture and color choices below it.
The page has no navigation header, footer, promotional copy or freeze/demo controls.
The browser tab is titled Strok and uses an empty favicon.

Interface typography uses Cozette Vector v1.30.0, the browser-compatible outline
of the Cozette bitmap font. It is bundled locally under the MIT license; its
copyright and license are in `web/assets/Cozette-LICENSE.txt`. Source:
https://github.com/the-moonwitch/Cozette/releases/tag/v.1.30.0.
Source Code Pro remains the renderer/canvas glyph font so native shape matching
and painted character shapes continue to agree. The interface background and
paper palette use warm off-white (`#f4f1e8`).

The generated demo starts at Saturn and cycles through Mercury, Venus, Earth,
Mars, Jupiter, Uranus and Neptune, spending ten seconds on each planet with a
1.4-second crossfade. Procedural surfaces rotate under directional lighting;
Saturn has rings drawn behind and in front of the sphere. These are stylized
illustrations rather than astronomical textures. Reduced motion holds Saturn
still. No remote assets are needed. Only the grid dimensions remain overlaid
at the bottom right; the source and study-number badges are removed.

The dropper after the pink palette opens the browser color picker. A custom
color tints the character output against a dark background and is saved with
each capture, including PNG exports. Selecting a preset restores that palette;
Reset restores Blocks, Original and 144 columns. The capture format button
cycles Single → Strip ×2 → Strip ×3 → Strip ×4 → Single. Each strip frame uses
the selected timer, with at least a one-second gap after the first frame.

### Mobile capture flow

At widths up to 760px, timer, shutter and strip count stay in a fixed bottom bar
with safe-area padding. Page content reserves space below the bar. Tapping the
shutter returns to the viewfinder before the countdown; strip countdowns show
the current photo number. A completed capture brings the contact sheet into
view and focuses the new PNG download. Preview and settings DOM order follows
the mobile visual order and returns to the desktop order across the breakpoint.

Mobile effect choices use two columns and controls have at least 44px-tall touch
targets. Saved photos use one column with bounded preview heights and larger
save/share actions. Landscape hides the large wordmark and constrains the viewfinder height so the preview fits above the shutter dock. Browsers without
element fullscreen use an expanded viewfinder that closes from its button or
Escape. The fixed capture bar is below the expanded viewfinder's stacking level.

Browser checks cover fixed-shutter visibility while editing, touch-target
heights, fullscreen fallback, strip progress/cancellation, capture-to-save focus,
layout at 320/390/768px and WCAG AA checks. Screenshots additionally inspect
320×568 portrait and 740×390 landscape. Physical camera permissions, operating
system sharing sheets, hardware heat and battery behavior still require real
iOS/Android device testing.

### Capture delivery animation

A completed capture briefly jitters the viewfinder, feeds a receipt from a bottom
print slot in 24 steps, settles it, and slides it into the new gallery position.
The sequence takes about two seconds. The PNG and text are saved before motion
starts; interruption (including Escape or hiding the tab) reveals the saved card
and removes the temporary paper/slot. Controls cannot start another capture while
delivery is running. Reduced motion skips this sequence entirely. The mobile
instruction and strip icon remain visible. Capture success banners, the contact
sheet label and the gallery's explanatory copy have been removed.

Browser checks cover the four print phases, overlay cleanup, interrupting a print
without losing the photo, and a full-motion WebKit mobile delivery. The animation
was also inspected at 10% playback speed in Chromium.
