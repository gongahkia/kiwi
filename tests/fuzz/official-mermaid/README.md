# Official Mermaid fuzz corpus

These fixtures are generated from the official Mermaid syntax examples and
reduced to the parser subset currently implemented in `kumeyuri-core`.

Per-fixture source URLs, Mermaid version, root type, and expected parser/render
status are stored in `manifest.json`.

Generation rule: keep the documented diagram headers and statement families,
rename labels/ids, and combine supported examples into compact parser fixtures.

Run `npm run import:official-mermaid` to refresh the reduced fixtures and
`npm run import:official-mermaid -- --check` to verify that fixtures and
`manifest.json` are current.
