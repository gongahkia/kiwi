# Golden Reference Corpora

These corpora are third-party reference outputs for visual parity benchmarking.
They are vendored at pinned upstream commits so diffs are reviewable and
repeatable.

Do not edit vendored files in place. Refresh by replacing a full source subtree
from the pinned upstream commit and updating `corpora.toml`.

## Sources

* `beautiful-mermaid/`
  * Upstream: https://github.com/lukilabs/beautiful-mermaid
  * Commit: `2ac8bbbb060ca0a65a6a21f3200bd99b1587b488`
  * Copied path: `src/__tests__/testdata`
  * License: MIT, copied at `beautiful-mermaid/LICENSE`
* `mermaid-ascii/`
  * Upstream: https://github.com/AlexanderGrooff/mermaid-ascii
  * Commit: `fba8b40f14a309180df0b2943c2695c7a4e5a2e2`
  * Copied path: `cmd/testdata`
  * License: MIT, copied at `mermaid-ascii/LICENSE`
