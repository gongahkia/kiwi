# ADR 0040: automatic initial-shell integration injection

## Context

The reversible v1 Bash, Zsh, and fish assets from ADR 0031 were usable only
when a user manually sourced them. That left Kiwi's default shell without the
documented OSC 7/133 metadata unless the user edited a dotfile, despite the
application already knowing the initial shell, launch environment, and
versioned integration directory.

## Decision

When `shell-integration = auto` (the default), Kiwi prepares only its initial
default Bash, Zsh, or fish command. It does not edit a dotfile:

- Bash runs an injected `--rcfile` that first sources the user's normal
  readable `.bashrc`, then enables `KIWI_SHELL_INTEGRATION=1` and sources the
  v1 Bash asset.
- Zsh uses a staged `ZDOTDIR`: its `.zshenv` sources the user's normal
  `.zshenv`; its staged `.zshrc` restores the original `ZDOTDIR`, sources the
  user's normal `.zshrc`, then enables and sources the v1 Zsh asset.
- Fish uses `--init-command`, which runs after fish has read its normal
  configuration, to enable and source the v1 fish asset.

Explicit child commands and shells started later inside Kiwi are deliberately
unchanged. They may use the existing manual-source blocks. An unsupported
shell basename, a missing integration resource, or `shell-integration = none`
leaves the original launch untouched. The configuration environment override
is `KIWI_SHELL_INJECTION=none`.

## Consequences

The normal first shell gains advisory shell metadata without persistent user
configuration changes. This is intentionally not a generic shell wrapper or
a promise that arbitrary custom startup paths will be injected. The staged
launchers are deterministic-tested with disposable shell configurations;
real user startup files remain outside repository control. SSH has a separate
explicit remote-terminfo helper and does not alter this decision.

## References

- [ADR 0031](0031-opt-in-shell-integration-assets.md)
- [shell integration v1](../SHELL_INTEGRATION.md)
- [GNU Bash invocation](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)
- [Zsh startup files](https://zsh.sourceforge.io/Doc/Release/Files.html)
- [Fish invocation](https://fishshell.com/docs/current/cmds/fish.html)
