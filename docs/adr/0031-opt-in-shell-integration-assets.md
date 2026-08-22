# ADR 0031: opt-in versioned shell integration assets

**Status:** Superseded for initial-shell launch behavior by [ADR 0040](0040-automatic-initial-shell-injection.md). The versioned asset and manual-source safety boundary remain in force.

## Context

Kiwi's bounded OSC 7/133 parser and command-region model need a practical way
for supported shells to emit the documented marker lifecycle. Automatically
editing a user's dotfiles, inferring a shell configuration, or sourcing a
network-fetched helper would change shell behavior outside the terminal's
control and make removal unclear.

## Decision

Kiwi ships `integrations/v1/kiwi.bash`, `kiwi.zsh`, `kiwi.fish`, and `kiwi.nu`. They are
sourceable assets, not installed executables and not part of `make run`.
Activation requires all of an interactive shell, `TERM=xterm-kiwi`, and
`KIWI_SHELL_INTEGRATION=1`; every other case returns silently. The release
guide provides explicit configuration and removal snippets, and Kiwi never
writes configuration files or contacts a network endpoint.

The scripts use their native hook surfaces to emit BEL-terminated OSC 7 and
OSC 133 records. They preserve the user's configured prompt rather than
replacing it: Bash prepends a scalar `PROMPT_COMMAND` and uses `PS0`, Zsh adds
precmd/preexec hooks, fish registers prompt/preexec/postexec handlers, and
Nushell prepends `pre_prompt`/`pre_execution` hooks.
Bash array-form `PROMPT_COMMAND` is deliberately unsupported in v1 and leaves
the integration inactive. Each script exposes `kiwi_shell_integration_uninstall`
to remove the hooks it added; Bash restores the saved scalar prompt variables.
Nushell restores the hooks record it saved at activation, so hooks installed
after activation must be restored separately.

The CWD encoder accepts only absolute paths, percent-encodes non-unreserved
bytes, limits the emitted URI to 2,048 bytes, and includes only a bounded safe
ASCII hostname. It skips unsafe or oversized OSC 7 data but still emits the
bounded marker lifecycle. The terminal parser remains the sole acceptance and
state boundary; emitted metadata has no path-access, execution, renderer, or
diagnostics privilege.

## Consequences

Supported users get a documented, reversible opt-in integration without a
prompt framework dependency. Prompt customizations remain in ownership of the
shell configuration, and a shell that cannot preserve the v1 contract stays
silent rather than guessing. The scripts' captured byte stream is tested by
sourcing each in a disposable interactive shell and replaying it through the
same parser/state model as production output.

## References

- [iTerm2 proprietary escape codes](https://iterm2.com/documentation-escape-codes.html)
- [Microsoft shell integration sequences](https://learn.microsoft.com/en-ca/windows/terminal/tutorials/shell-integration)
- [ADR 0027](0027-bounded-shell-integration-metadata.md)
