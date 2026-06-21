# Blitter Ladder

`--mode auto` resolves once at startup from `TerminalCaps`. Detection uses environment variables, the allowlist, optional FreeType cmap checks from `--font`, and `--caps` overrides. It does not send terminal query escapes.

`--render-mode pixel` and `hybrid` are accepted as ladder intent, but pixel transport is still a Phase N item; current auto resolution stays on the best text rung.

| TERM_PROGRAM / font caps | `--render-mode` | Resolved text mode |
|---|---|---|
| truecolor + octant cmap | `text` | `octant` |
| truecolor + sextant cmap, no octants | `text` | `sextant` |
| truecolor + braille cmap only | `text` | `luminance --charset braille` |
| truecolor, no packed block cmap | `text` | `halfblock` |
| no truecolor + structure option passed | `text` | `structure` |
| no truecolor + no structure option | `text` | `luminance` |
| graphics-capable terminal + `pixel`/`hybrid` | `pixel`/`hybrid` | best text rung until Phase N |

Test coverage: `auto_mode_tests` covers each row above except Phase N pixel transport, which is documented as pending.
