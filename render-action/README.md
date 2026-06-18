# kumeyuri/render-action

Render Mermaid `.mmd` files to SVG/GIF artifacts in pull requests.

```yaml
name: Render diagrams

on:
  pull_request:

jobs:
  render:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6.0.3
      - uses: kumeyuri/render-action@v1
        with:
          source: |
            docs/**/*.mmd
            examples/**/*.mmd
          formats: svg,gif
          theme: github
          padding: 12
```

By default the action writes files under `kumeyuri-output/` and uploads them as
the `kumeyuri-rendered` artifact. It installs `kumeyuri` with:

```bash
cargo install --git https://github.com/gongahkia/kumeyuri kumeyuri-cli --locked
```

Override `kumeyuri-command` when the workflow already installed the binary.

## Inputs

| Input | Default | Notes |
| --- | --- | --- |
| `source` | `**/*.mmd` | Newline, comma, or space separated files/globs. |
| `output-dir` | `kumeyuri-output` | Rendered artifact directory. |
| `formats` | `svg,gif` | Any `kumeyuri render --format` value. |
| `theme` | `github` | Passed to `--theme`. |
| `dark-theme` | empty | Passed to SVG renders only. |
| `charset` | empty | Optional `ascii` or `unicode`. |
| `width` | empty | Optional minimum text cell width. |
| `padding` | `12` | Passed to `--padding`. |
| `font` | empty | Passed to `--font`. |
| `kumeyuri-command` | `kumeyuri` | Binary command. |
| `install-command` | cargo install from git | Runs if `kumeyuri-command` is unavailable. |
| `fail-on-empty` | `true` | Fail when no `.mmd` files match. |
| `upload-artifact` | `true` | Upload rendered files with `actions/upload-artifact`. |
| `artifact-name` | `kumeyuri-rendered` | Artifact name. |

## Outputs

| Output | Meaning |
| --- | --- |
| `file-count` | Number of `.mmd` files rendered. |
| `rendered-count` | Number of output files written. |
| `output-dir` | Rendered artifact directory. |
