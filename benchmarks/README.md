# Renderer benchmark fixtures

Run the enforced fixture suite with:

```sh
make benchmark-effects
```

Run the clean 1,000-frame local evidence fixture with:

```sh
make benchmark-renderer FRAMES=1000
```

The harness uses a deterministic fixture graphics boundary and font, fixed seed
`31337`, integer `16667` microsecond frame deltas, the continuous-output scene, and
both `120×40` and `240×80` grids. It measures a 60-frame warm-up followed by three
independent 30-frame timing samples. Each sample separately measures one GC-stopped
steady-state frame for bytes allocated per frame. The small allocation window prevents
the deliberately allocation-heavy full-grid Kinetic fixture from retaining an
unbounded measurement buffer.

Named fixtures are `clean`, `crt`, `kinetic`, `combined`, `effects_disabled`, and
`quarantined`. The combined fixture is CRT plus Kinetic; the quarantined fixture fails
once during warm-up and is excluded from subsequent dispatch. The report includes
median frame time, FPS, GC-stopped bytes per frame, retained resource counts,
steady-state resource growth, quarantine state, and effect overhead relative to the
clean fixture from the same process. `make benchmark-effects` runs each clean/effect
pair in a fresh LuaJIT process so Kinetic's deliberately allocation-heavy full-grid
fixture cannot alter later allocation measurements.

`baselines.lua` is an explicit environment-keyed baseline ledger. A baseline includes
the fixture dimensions, frame count, warm-up, sample count, median frame time, bytes
per frame, and steady-state retained-resource growth. The environment signature covers
the LuaJIT version, OS/architecture, fixture graphics backend, and fixture font. An
unmatched environment or measurement configuration reports results but does not fail.

For a matching baseline, the harness fails when median frame time rises by more than
15%, or bytes per frame rise by more than the greater of 15% or 128 bytes. It also
fails for retained canvas, shader, font, or effect-instance growth; a shader
compilation during steady state; or temporary-canvas growth. Baseline updates require
an explicit ledger edit and a reason.

This is a deterministic Lua/fixture measurement, not a portable GPU FPS claim. Real
LÖVE, driver, window, DPI, and GPU measurements remain environment-specific.
