# Shell integration v1

Kiwi can consume advisory OSC 7 current-directory records and OSC 133 prompt,
command, output, and completion markers. The versioned scripts in
`integrations/v1/` emit those sequences for Bash, Zsh, and fish. They do not
edit shell configuration, make network requests, access a path, execute
commands, or change a prompt unless explicitly sourced in an interactive Kiwi
session.

## Enable it

Pick the script for the shell that starts inside Kiwi and add one of these
blocks to that shell's interactive configuration file. Replace
`/absolute/path/to/kiwi` with this checkout's absolute path.

```sh
# ~/.bashrc
if [[ $TERM == kiwi ]]; then
  export KIWI_SHELL_INTEGRATION=1
  source /absolute/path/to/kiwi/integrations/v1/kiwi.bash
fi
```

```sh
# ~/.zshrc
if [[ $TERM == kiwi ]]; then
  export KIWI_SHELL_INTEGRATION=1
  source /absolute/path/to/kiwi/integrations/v1/kiwi.zsh
fi
```

```fish
# ~/.config/fish/config.fish
if status is-interactive; and test "$TERM" = kiwi
    set -gx KIWI_SHELL_INTEGRATION 1
    source /absolute/path/to/kiwi/integrations/v1/kiwi.fish
end
```

Every script independently requires an interactive shell, `TERM=kiwi`, and
`KIWI_SHELL_INTEGRATION=1`; otherwise it returns without output or prompt
changes. The Bash script declines to activate when `PROMPT_COMMAND` is an
array, because v1 only preserves the scalar form. The scripts are safe to
source again after activation.

## Behavior and limits

At the first prompt each script emits a bounded `OSC 7;file://… BEL` record
followed by `OSC 133;A BEL`. Before each command it emits `OSC 133;B BEL` and
`OSC 133;C BEL`; after it finishes it emits `OSC 133;D;<status> BEL`, then the
next prompt emits current-directory and `A` again. Bash uses `PS0` plus
`PROMPT_COMMAND`; Zsh and fish use their native pre-command and prompt hooks.

The current directory is URI-percent-encoded and emitted only when it is an
absolute path at most 2,048 bytes. A hostname is included only when it is
ASCII `A-Z`, `a-z`, `0-9`, `.`, `_`, or `-`, and no longer than 255 bytes.
Otherwise the script omits the OSC 7 record; the OSC 133 lifecycle markers
continue. These bounds match Kiwi's accepting parser but do not make the URI a
trusted local path. See [ADR 0027](adr/0027-bounded-shell-integration-metadata.md)
and [the conformance contract](CONFORMANCE.md#osc-7-and-osc-133-shell-metadata).

## Disable or remove it

Remove the matching block above from the shell configuration file and start a
new shell. To undo the active integration immediately, run:

```sh
kiwi_shell_integration_uninstall
```

The helper removes only the hooks installed by v1. In Bash it restores the
scalar `PROMPT_COMMAND` and `PS0` values present when the script was sourced.
It does not revert unrelated prompt changes made after activation.

## Verification

The deterministic suite sources each script in a disposable interactive shell,
captures the documented OSC byte stream, and feeds it through Kiwi's parser
and command-region model:

```sh
make test
```

For a direct local syntax check where all three shells are installed:

```sh
bash -n integrations/v1/kiwi.bash
zsh -n integrations/v1/kiwi.zsh
fish -n integrations/v1/kiwi.fish
```
