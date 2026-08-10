# Text laboratory report

The text laboratory is a development-only comparison tool. Normal Kiwi startup
uses the `atlas` backend and ignores experimental backend requests.

```sh
make text-lab
make text-lab BACKENDS=atlas,msdf
make text-lab-demo BACKEND=atlas
```

`make text-lab` writes an ignored `bench/results/*-text-lab.json` artifact.
`BACKENDS` is a comma-separated list of at most four lowercase backend names;
the report always prepends `atlas`. `make text-lab-demo` is the corresponding
native review command. It alone enables `KIWI_TEXT_LAB=1` and passes
`KIWI_TEXT_LAB_BACKEND`, so neither variable is a production user setting.

The artifact has three kinds of evidence:

| Section | Meaning | Do not infer |
| --- | --- | --- |
| `measured_facts` and backend `measurements` | CPU samples for `backend:update` after parser/state construction, shared corpus counts, backend descriptor, font inventory, and shape settings | GPU, compositor, end-to-end latency, or visual quality |
| `unavailable_environments` | Requested backend resolved to the explicit atlas fallback | That the prototype executed or matched the baseline |
| `inference` and `recommendation` | Explicit limits and the status requiring human review | Automatic promotion or retirement |

## Review template

Fill this alongside the JSON artifact and native screenshots. State
`unavailable` rather than supplying a value that was not measured.

```text
artifact: <path and SHA-256>
baseline/requested backend: <descriptor requested/active/fallback>
candidate backend: <descriptor requested/active/fallback, or unavailable>
revision and environment: <commit, kernel, adapter/driver, governor, LuaJIT>
font and shaping: <primary/fallback paths, pixel height, ligatures/calt>
corpus: <version and six scenario counts>
CPU scope/results: <p50/p95/p99 per comparable scenario, or unavailable>
native screenshots: <atlas path>, <candidate path or unavailable>
semantic review: <width, EGC, fallback, glyph/instance/cache counter findings>
visual review: <missing/overlap/clipping/wide-cell/ligature/dense-UI findings>
failures/fallbacks: <stable reason and affected scenario>
recommendation: <promote / retain experimental / retire / unavailable>
rationale: <measured facts separate from inference>
```

Promote a prototype only when its artifact uses the unchanged
`kiwi-text-corpus-v1`, equivalent font/shaping/content-scale and host settings,
preserves terminal-column and grapheme ownership semantics, retains bounded
resource/lifetime coverage, exposes deterministic atlas fallback, has matching
native visual evidence, and passes `make check`. Retire it when those conditions
cannot be met or its unavailable/failure route is not clear, while retaining
the reproducible atlas baseline.
