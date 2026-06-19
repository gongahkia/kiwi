# Kumecast v1

Kumecast is the planned portable timeline format for replaying a parsed
kumeyuri render without reparsing Mermaid source. This page specifies the v1
JSON shape; encoder, decoder, CLI commands, gzip, and web-player support remain
separate TODO items.

The machine-readable schema lives at:

```text
docs/spec/kumecast-v1.schema.json
```

## Container

| Field | Required | Purpose |
| --- | --- | --- |
| `version` | yes | Format version. Must be `1`. |
| `source` | yes | Original diagram metadata and optional content hash. |
| `theme` | yes | Theme name and charset used to create frames. |
| `timeline` | yes | Ordered rendered frames. |
| `metadata` | no | Flat string/number/boolean/null metadata for producers. |

## Source

```json
{
  "diagramType": "flowchart",
  "mermaid": "graph TD\nA --> B",
  "sha256": "22c4701023872930cbfb9629950f8f8f62aded2537e214850117520fbeb50b7b"
}
```

`sha256` is optional and hashes the UTF-8 Mermaid source when present.

## Timeline

```json
{
  "repeat": false,
  "frames": [
    {
      "durationMs": 550,
      "width": 15,
      "height": 5,
      "cells": [
        {
          "glyph": "A",
          "style": {
            "foreground": "#24292f",
            "background": "#ffffff",
            "bold": true
          },
          "marker": "node:A"
        }
      ],
      "markers": [
        {
          "id": "node:A",
          "kind": "node",
          "region": {
            "x": 0,
            "y": 0,
            "width": 5,
            "height": 3
          }
        }
      ]
    }
  ]
}
```

Cells are row-major and represent the rendered `Frame::cells()` output. A
consumer must reject a frame when `cells.length != width * height`.

## Compatibility rules

- Readers must reject unknown top-level fields.
- Readers must reject unsupported `version` values.
- Readers may ignore unknown `metadata` keys.
- Readers must preserve frame order and frame duration.
- Writers should include `source.mermaid` unless redaction is required.
- Writers should use lowercase hex RGB colors.

## Full schema

The schema is JSON Schema draft 2020-12. It is duplicated in the adjacent
`.schema.json` file so CI and downstream tools can parse it directly.
