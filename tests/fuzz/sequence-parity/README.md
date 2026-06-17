# Sequence parity fixtures

Fixtures track parser parity against Mermaid sequence syntax documented at `https://mermaid.js.org/syntax/sequenceDiagram.html` for version `11.15.0`.

`message_without_colon.mmd` is intentionally rejected: Mermaid `11.15.0` rejects `Alice->>Bob`, while accepting `Alice->>Bob:`.
