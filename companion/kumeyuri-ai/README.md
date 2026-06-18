# kumeyuri-ai

Optional companion crate for AI-assisted kumeyuri layout rewrites.

This package is intentionally isolated from the main Cargo workspace. It defines
the stable request/diagnostic/rewrite types and the `LayoutAssistant` trait that
future provider implementations can satisfy without making `kumeyuri-cli`
depend on an AI SDK.

Initial scope:

- accept Mermaid source plus layout diagnostics from `kumeyuri lint --json`
- return rewritten Mermaid source plus a short summary
- resolve BYOK provider API keys from `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
  and `OPENROUTER_API_KEY`
- define provider configuration/request/response abstractions for OpenAI,
  Anthropic, OpenRouter, and local llama.cpp backends
- validate that provider output is non-empty before any caller applies it

Out of scope here:

- network calls to provider APIs
- applying rewrites to files
- dynamic loading from the main CLI
