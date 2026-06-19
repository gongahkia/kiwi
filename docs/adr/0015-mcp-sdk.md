# ADR 0015: MCP SDK

## Status

Accepted.

## Context

Phase 6 adds a Model Context Protocol server with stdio and HTTP/SSE
transports, tool discovery, and smoke tests. The open question was whether to
use `rmcp` or write a thin MCP transport by hand.

Inputs reviewed on 2026-06-19:

* The official MCP Rust SDK repository is `modelcontextprotocol/rust-sdk` and
  identifies `rmcp` as the SDK crate:
  <https://github.com/modelcontextprotocol/rust-sdk>.
* crates.io publishes `rmcp` 1.7.0:
  <https://crates.io/crates/rmcp>.
* docs.rs describes `rmcp` as the official Rust SDK for building MCP servers and
  clients:
  <https://docs.rs/crate/rmcp/latest>.

## Decision

Use `rmcp` for kumeyuri's MCP server implementation.

Do not hand-roll protocol parsing, request routing, or schema serialization.
kumeyuri should keep its own boundary at tool implementation, process spawning,
input limits, and security policy.

## Consequences

* The implementation follows the current official Rust MCP surface instead of a
  local protocol copy.
* stdio and HTTP transports should be implemented through `rmcp` transport
  facilities where available.
* MCP tool code must still enforce kumeyuri limits: bounded input size, no shell
  interpolation, explicit file/network permissions, and deterministic renderer
  options.
* If `rmcp` changes incompatibly, keep the dependency behind a `kumeyuri mcp`
  module boundary.

## Rejected

* Thin handwritten transport: lower dependency count, but higher protocol drift
  risk now that an official Rust SDK is available and published.
* Unofficial Rust MCP crates: viable alternatives, but unnecessary while the
  official SDK is active.
