# Official Mermaid fuzz corpus

These fixtures are reduced from the official Mermaid syntax examples and kept in
the parser subset currently implemented in `kumeyuri-core`.

Per-fixture source URLs, Mermaid version, root type, and expected parser/render
status are stored in `manifest.json`.

Generation rule: keep the documented diagram headers and statement families,
rename labels/ids, and combine supported examples into compact parser fixtures.

Run `npm run import:official-mermaid` to refresh `manifest.json` from the
checked-in fixture list and `npm run import:official-mermaid -- --check` to
verify that fixture files and `manifest.json` are current.
