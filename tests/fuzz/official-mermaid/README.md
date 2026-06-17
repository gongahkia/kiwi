# Official Mermaid fuzz corpus

These fixtures are generated from the official Mermaid syntax examples and
reduced to the parser subset currently implemented in `kumeyuri-core`.

Sources:

- https://mermaid.ai/open-source/syntax/flowchart.html
- https://mermaid.ai/open-source/syntax/sequenceDiagram.html
- https://mermaid.ai/open-source/syntax/stateDiagram.html
- https://mermaid.ai/open-source/syntax/examples.html

Generation rule: keep the documented diagram headers and statement families,
rename labels/ids, and combine supported examples into compact parser fixtures.

Run `npm run import:official-mermaid` to refresh the reduced fixtures and
`npm run import:official-mermaid -- --check` to verify that fixtures and
`manifest.json` are current.
