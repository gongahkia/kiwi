# ADR 0011: SVG Animation Mode

## Status

Accepted.

## Context

kumeyuri needs animated SVG output for READMEs, docs, browser embeds, and static
site hosts. The SVG renderer currently has two animation strategies:

* SMIL `<animate>` elements on per-frame opacity.
* CSS `@keyframes` on per-frame groups.

Both strategies must preserve accessibility metadata, text fallback metadata,
dark-mode CSS, reduced-motion CSS, and progress dots after the sanitizer path
used by project tests. The project already gates this through
`npm run test:svg-sanitizer` and `npm run test:svg-reduced-motion`.

## Decision

Keep SMIL as the default SVG animation mode and keep CSS keyframes as an
explicit fallback mode.

The public configuration stays:

```text
SvgAnimationMode::Smil
SvgAnimationMode::CssKeyframes
```

The TypeScript/WASM API continues to expose `svgAnimation: "smil" |
"css-keyframes"`.

## Consequences

* Default SVG output stays compact and direct: each frame group owns an opacity
  animation.
* Hosts that prefer or require CSS animation can opt into CSS keyframes without
  changing the frame model.
* Sanitizer and reduced-motion tests must continue to cover both modes.
* If a target host strips SMIL in practice, users can switch to CSS keyframes
  without waiting for a renderer rewrite.

## Rejected

* CSS-keyframes-only output: viable, but it removes a compact default that
  passes the current sanitizer gate.
* SMIL-only output: too brittle for hosts that strip or disable SMIL while still
  allowing style tags.
* JavaScript-driven SVG playback: rejected for README/static-doc contexts and
  stricter sanitizer environments.
