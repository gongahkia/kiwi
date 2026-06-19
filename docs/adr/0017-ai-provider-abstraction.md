# ADR 0017: AI Provider Abstraction

## Status

Accepted

## Context

Phase 8 adds an optional `kumeyuri-ai` companion boundary for layout rewrites.
The main CLI must remain usable without AI SDKs, network credentials, or provider
feature churn. The companion currently exposes:

- `LayoutAssistant` for source-plus-diagnostics to rewrite conversion;
- `ProviderClient` for provider completion calls;
- `AiProvider` covering OpenAI, Anthropic, OpenRouter, and local llama.cpp;
- `ProviderConfig`, `ProviderRequest`, and `ProviderResponse` as stable shared
  transport-neutral data types;
- BYOK resolution through `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and
  `OPENROUTER_API_KEY`;
- a dynamic ABI version symbol so `kumeyuri-cli` can load a companion library
  without linking provider implementations.

The unresolved choice was whether each backend should live behind separate
crate features, or whether the companion should expose one shared trait surface
with provider selection as data.

## Decision

Use a single companion crate with shared provider traits and provider selection
encoded in `AiProvider` / `ProviderConfig`. Do not split OpenAI, Anthropic,
OpenRouter, and llama.cpp support into first-party per-provider crate features
for ABI 1.x.

Provider implementations may still live in downstream crates or binaries, but
they should satisfy the shared `ProviderClient` and `LayoutAssistant` contracts.
The main CLI should continue to load the companion dynamically and should not
gain direct dependencies on provider SDKs.

## Consequences

- The dynamic ABI remains small: the CLI only needs to verify the companion ABI
  and pass layout rewrite data across the boundary.
- Tests can exercise provider selection, API-key behavior, and rewrite
  validation without making network calls.
- Adding a provider requires extending `AiProvider` and compatibility tests, so
  provider growth is intentional rather than hidden behind feature sprawl.
- Provider SDK churn stays outside the main workspace and release path.
- Advanced users can still build alternate companion libraries as long as they
  honor the ABI and trait contracts.

## Rejected

### Per-provider first-party crate features

Rejected for ABI 1.x. Feature-gating each provider would multiply build
variants, push provider SDK dependency churn into the official companion release
surface, and make compatibility harder to explain. It also does not help the
main CLI, which intentionally loads the AI boundary dynamically.

### Provider-specific traits

Rejected. The layout assistant needs text completion plus provider config, not
provider-specific streaming, tool-call, or multimodal APIs. Provider-specific
traits would expose capability differences that the layout rewrite workflow does
not currently need.
