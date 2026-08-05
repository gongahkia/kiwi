# Screenshot scenarios

Screenshot scenarios are deterministic visual inspection fixtures, not CI pixel
goldens. Each uses a `120×40` terminal, `960×640` viewport, seed `31337`, timestamp
`33334` microseconds, fixture terminal output, and fixed built-in parameters.

Available scenario IDs are `clean`, `crt`, `kinetic`, and `combined`. Validate all
scene construction and drawing without capture with:

```sh
make screenshot-scenarios
```

Capture one scene manually on a local LÖVE installation:

```sh
STANCZYK_SCREENSHOT_SCENARIO=combined \\
STANCZYK_SCREENSHOT_DIR=screenshots/manual \\
love .
```

The command writes to LÖVE's save directory and reports the absolute output location.
The default path is `screenshots/manual`. Names are
`<id>-120x40-t33334-seed31337.png` and a matching `.json` metadata file. Metadata
records the scenario ID, dimensions, seed, timestamp, output PNG path, and capture
environment. Captures are local evidence and are intentionally not committed as
cross-platform pass/fail pixels.

CI pixel comparison remains deferred until its execution environment pins an OS image,
LÖVE version/build, graphics backend, font asset and hash, DPI/scale, GPU or software
renderer, and capture colour configuration.
