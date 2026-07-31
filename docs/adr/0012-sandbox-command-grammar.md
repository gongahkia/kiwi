# ADR-0012: Stanczyk sandbox command grammar

- Status: Accepted
- Date: 2026-07-31

## Context

Sandbox commands need deterministic, bounded argument handling without inheriting a
host shell, locale, environment, or shell-expansion semantics. Calling this syntax a
POSIX parser would create an unsupported compatibility promise.

## Decision

Stanczyk v1 defines a byte-oriented **Stanczyk sandbox command grammar**. It accepts a
bounded Lua byte string and neither decodes, normalises, validates, nor case-folds
UTF-8. ASCII space (`0x20`) and horizontal tab (`0x09`) are the only unquoted argument
delimiters. All other bytes, including NUL and invalid UTF-8, remain opaque bytes.

The tokenizer has `unquoted`, `single_quoted`, and `double_quoted` states. In
unquoted and double-quoted states, backslash appends exactly the following byte. In a
single-quoted state, every byte other than the closing quote is literal. Adjacent
quoted and unquoted fragments concatenate into one argument, and empty quotes begin
an empty argument. An input containing only delimiters produces zero arguments.

The default bounds are 65,536 input bytes, 64 arguments, and 4,096 bytes per
argument. Callers may tighten, but not raise, those bounds. Failures use
`sandbox_command_error` with a stable `detail.reason`, zero-based byte offset, and
tokenizer state. Required reasons are `unterminated_single_quote`,
`unterminated_double_quote`, `trailing_escape`, `input_too_large`,
`too_many_arguments`, and `argument_too_large`.

Tokenization completes before command registry lookup. A failed tokenization has no
partial argv, lookup, callback, registry mutation, or sandbox-state mutation. A
successful zero-argument result is a no-op. For all other results, `argv[1]` is the
exact command-name byte string. The dispatcher gives callbacks and callers independent
argv copies; registry definitions remain copy-isolated.

This grammar does not implement variable, environment, command, arithmetic, tilde,
pathname, brace, alias, comment, redirection, pipeline, separator, job, control
operator, subshell, here-document, or escape-sequence expansion. `$`, `*`, `?`, `|`,
`>`, `<`, `;`, `&`, `#`, parentheses, and backticks are ordinary bytes. It is not a
POSIX shell parser and does not claim POSIX-shell compatibility.

## Consequences

Sandbox command invocation is deterministic for equal input bytes and configured
bounds, independent of locale, Unicode libraries, platform shells, environment,
filesystem state, and unordered iteration. Features that require shell-language
semantics need a separate, explicitly approved command language design.
