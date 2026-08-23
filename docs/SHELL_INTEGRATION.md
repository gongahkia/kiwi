# Shell integration v1

Kiwi can consume advisory OSC 7 current-directory records and OSC 133 prompt,
command, output, and completion markers. The versioned scripts in
`integrations/v1/` emit those sequences for Bash, Zsh, fish, and Nushell. Kiwi injects
the relevant script into its **initial default shell** without editing a
dotfile: Bash first sources the usual `.bashrc`, Zsh restores the user's
`ZDOTDIR` before sourcing `.zshrc`, fish evaluates its normal configuration
before its init command, and Nushell loads the asset with its documented
`--execute` then `--interactive` startup form. Explicit `-- command …` launches and shells started
from inside the terminal are not injected.

The injection is enabled by default as `shell-integration = auto`. Disable it
for every default shell with `shell-integration = none` in Kiwi's configuration
file, or `KIWI_SHELL_INJECTION=none` for one launch. The scripts themselves
still require an interactive `TERM=xterm-kiwi` shell and
`KIWI_SHELL_INTEGRATION=1`; a direct/manual shell launch must set that variable
before sourcing an asset. Neither path edits shell configuration, accesses a
path, or performs a network request.

## Manual setup and switched shells

Automatic injection covers only the first supported shell Kiwi launches. To
retain integration after `exec zsh`, `nix-shell`, or another shell transition,
source the matching asset from that shell's interactive configuration. Replace
`/absolute/path/to/kiwi` with this checkout's absolute path.

```sh
# ~/.bashrc
if [[ $TERM == xterm-kiwi ]]; then
  export KIWI_SHELL_INTEGRATION=1
  source /absolute/path/to/kiwi/integrations/v1/kiwi.bash
fi
```

```sh
# ~/.zshrc
if [[ $TERM == xterm-kiwi ]]; then
  export KIWI_SHELL_INTEGRATION=1
  source /absolute/path/to/kiwi/integrations/v1/kiwi.zsh
fi
```

```fish
# ~/.config/fish/config.fish
if status is-interactive; and test "$TERM" = xterm-kiwi
    set -gx KIWI_SHELL_INTEGRATION 1
    source /absolute/path/to/kiwi/integrations/v1/kiwi.fish
end
```

```nu
# ~/.config/nushell/config.nu
# `source` requires a parse-time literal path; the asset itself stays inert
# outside an interactive Kiwi session.
if (($env.TERM? | default '') == 'xterm-kiwi') {
  $env.KIWI_SHELL_INTEGRATION = '1'
}
source "/absolute/path/to/kiwi/integrations/v1/kiwi.nu"
```

Every script independently requires an interactive shell, `TERM=xterm-kiwi`, and
`KIWI_SHELL_INTEGRATION=1`; otherwise it returns without output or prompt
changes. The Bash script declines to activate when `PROMPT_COMMAND` is an
array, because v1 only preserves the scalar form. The Nushell script retains
the pre-existing `pre_prompt` and `pre_execution` hooks and is safe to source
again after activation.

## Behavior and limits

At the first prompt each script emits a bounded `OSC 7;file://… BEL` record
followed by `OSC 133;A BEL`. Before each command it emits `OSC 133;B BEL` and
`OSC 133;C BEL`; after it finishes it emits `OSC 133;D;<status> BEL`, then the
next prompt emits current-directory and `A` again. Bash uses `PS0` plus
`PROMPT_COMMAND`; Zsh, fish, and Nushell use their native pre-command and
prompt hooks. Nushell's `pre_prompt` hook reads the bounded `LAST_EXIT_CODE`
value before it writes the next prompt lifecycle record.

The current directory is URI-percent-encoded and emitted only when it is an
absolute path at most 2,048 bytes. A hostname is included only when it is
ASCII `A-Z`, `a-z`, `0-9`, `.`, `_`, or `-`, and no longer than 255 bytes.
Otherwise the script omits the OSC 7 record; the OSC 133 lifecycle markers
continue. These bounds match Kiwi's accepting parser but do not establish that
the URI exists. On macOS, only the active session's empty, `localhost`, or
current-host URI may become the titlebar proxy URL; remote metadata clears that
affordance, and Kiwi does not stat, resolve, or automatically open it. See [ADR 0027](adr/0027-bounded-shell-integration-metadata.md)
and [the conformance contract](CONFORMANCE.md#osc-7-and-osc-133-shell-metadata).

## Disable or remove it

Set `shell-integration = none` (or `KIWI_SHELL_INJECTION=none`) to disable
automatic initial-shell injection. Remove a manual block above and start a new
shell to disable manual activation. To undo an active integration immediately,
run:

```sh
kiwi_shell_integration_uninstall
```

The helper removes only the hooks installed by v1. In Bash it restores the
scalar `PROMPT_COMMAND` and `PS0` values present when the script was sourced.
It does not revert unrelated prompt changes made after activation. Nushell
restores the complete `hooks` record saved when this asset was sourced, so
hooks added after activation must be re-added after uninstalling.

## SSH terminfo setup

`./script/kiwi-ssh -- user@host` (or `make kiwi-ssh SSH_ARGS='-- user@host'`)
is an explicit interactive-login helper. It copies Kiwi's already compiled
terminfo entry below `~/.cache/kiwi/terminfo/` on that remote account, then
opens an SSH PTY with `TERM=xterm-kiwi`, `COLORTERM=truecolor`, and a remote
`TERMINFO` pointing at that private cache. The exact first-level directory is
the local `tic` output (`78/xterm-kiwi` on the current macOS ncurses build;
some systems use `x/xterm-kiwi`), and the launcher preserves it during upload.
It does not alter `/etc`, the remote login profile, or local SSH configuration;
each invocation re-uploads the small compiled entry rather than retaining a
local destination cache.

The command intentionally accepts exactly one destination after `--` and no
remote command. It is not a general replacement for `ssh`. Repeat
`--ssh-option NAME=VALUE` for each OpenSSH configuration assignment; Kiwi
passes it as `-o NAME=VALUE` to the remote mkdir, `scp` transfer, probe,
fallback, and final SSH login. For example, use `./script/kiwi-ssh
--ssh-option Port=2222 -- user@host`. This preserves a non-default port without
relying on the incompatible meanings of `-p` in `ssh` and `scp`. Use
`--no-terminfo`
to open the conservative `xterm-256color` fallback without uploading, or
`--strict` to fail when setup cannot complete. The normal mode also falls back
to `xterm-256color` after a failed remote mkdir/upload, and prints that
downgrade to stderr. A successful local stub test proves argument and transfer
ordering only; it does not certify a particular real host, credential policy,
or remote terminal library.

## Verification

The deterministic suite sources every supported shell installed on the host in
a disposable interactive shell, captures the documented OSC byte stream, and
feeds it through Kiwi's parser and command-region model. Nushell-specific
checks are skipped only when `nu` is unavailable:

```sh
make test
```

For a direct local syntax check where all four shells are installed:

```sh
bash -n integrations/v1/kiwi.bash
zsh -n integrations/v1/kiwi.zsh
fish -n integrations/v1/kiwi.fish
nu --no-config-file -i -c 'source "integrations/v1/kiwi.nu"'
sh -n script/kiwi-ssh
```
