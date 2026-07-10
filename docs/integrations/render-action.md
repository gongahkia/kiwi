# Render Action

`render-action/` renders Mermaid `.mmd` files in GitHub Actions and uploads the
generated artifacts.

```yaml
name: Render diagrams

on:
  pull_request:

jobs:
  render:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: gongahkia/kumeyuri/render-action@v1
        with:
          source: |
            docs/**/*.mmd
            examples/**/*.mmd
          formats: svg,gif
          theme: github
          padding: 12
```

The action is published from the repository `v1` tag.
