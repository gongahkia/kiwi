# kumeyuri-ai

Optional companion crate for AI-assisted kumeyuri layout rewrites.

This package is intentionally isolated from the main Cargo workspace. It defines
the stable request/diagnostic/rewrite types and the `LayoutAssistant` trait that
future provider implementations can satisfy without making `kumeyuri-cli`
depend on an AI SDK.

Initial scope:

- accept Mermaid source plus layout diagnostics from `kumeyuri lint --json`
- return rewritten Mermaid source plus a short summary
- validate that provider output is non-empty before any caller applies it

Out of scope here:

- provider selection
- API key resolution
- applying rewrites to files
- dynamic loading from the main CLI
