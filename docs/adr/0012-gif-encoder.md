# ADR 0012: GIF Encoder

## Status

Accepted.

## Context

kumeyuri emits animated raster fallbacks for documentation, READMEs, and launch
assets. GIF support needs deterministic frame output from the shared `Timeline`
model, low setup cost in CI, and compatibility with workspace licensing and
cross-platform builds.

The candidate choices were:

* `gif` crate: pure Rust encoder, simple frame API, small dependency surface.
* `gifski` bindings: higher-quality GIF encoding, but a larger native stack and
  more CI/package complexity.

Current implementation in `kumeyuri-render-raster` uses `gif = "0.14.2"` and
encodes each timeline keyframe with `GifFrame::from_rgba_speed`.

## Decision

Use the `gif` crate for the built-in GIF renderer.

Keep `gifski` out of the default renderer until there is a measured quality or
size problem that justifies the extra dependency and distribution cost.

## Consequences

* GIF generation stays available in the Rust workspace without extra system
  libraries.
* CI can decode and assert generated GIFs with the same crate family.
* Output quality is adequate for text-frame diagrams but not tuned like gifski's
  palette/dithering pipeline.
* If launch assets require smaller or smoother GIFs, generate those as a
  separate release-media pipeline instead of changing the default renderer.

## Rejected

* `gifski` as the default renderer: better optimization potential, but too much
  dependency and packaging weight for the core CLI path.
* Shelling out to external GIF tools: non-deterministic in CI and inconsistent
  across platforms.
