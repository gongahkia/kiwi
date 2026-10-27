# Complete Intel macOS application corpus, 2026-10-27

At clean `e40c1d7` on Intel macOS 15.7.7, all
[12 extended local workflows](2026-10-27-macos-complete-applications.json)
and all [six loopback SSH workflows](2026-10-27-macos-current-ssh.json) passed.
This closes the previously recorded missing-fish qualification gap. The extended
local suite contains the eleven default cases plus the explicit Nushell case:
Bash, Zsh, fish, Nushell, Vim, Neovim, tmux, tmux/Neovim, less, top, the combined
shell/editor/pager workflow and its tmux counterpart.

Versions included Bash 3.2.57, Zsh 5.9, fish 4.9.3, Nushell 0.116.1, Vim 9.1,
Neovim 0.12.4, tmux 3.8, less 581.2 and OpenSSH 9.9p2. SSH cases exercise Bash
and the documented remote editor/tmux workflows, not remote fish or Nushell.
Each local workflow has its own temporary HOME/configuration/working directory.
Reports retain resize/checkpoint counts, parser diagnostics, saved-file checks
and whole/byte/random-chunk replay results.

## Private fish dependency

The [official fish macOS app bundle](https://github.com/fish-shell/fish-shell/releases/tag/4.9.3)
was extracted beneath ignored `.deps/qualification/fish-4.9.3`. Its archive
SHA-256 matched the release asset metadata:

```text
3619fa92d540ed0dff4816594429290550d21b92226e0523457e5f0242c5e9a8
```

Only the embedded `Contents/Resources/base/usr/local/bin` was prepended to the
test process PATH. The app launcher and installer were not run. Nushell came
from the existing private `.build/test-tools/nu-0.116.1-x86_64-apple-darwin` tool.
The initial Homebrew attempt was interrupted during its Python dependency build
when it selected source builds for a new toolchain; both owned process groups
were verified gone before testing. No login-shell or input-source change was made.

## Qualification boundary

These are actual application/PTY/parser/state workflows. They do not establish
native drawing, physical keyboard/IME delivery, VoiceOver, remote network/OS
coverage or sustained graphical responsiveness. The latest native history soak
still [fails its response gate](2026-10-27-unicode-cluster-pool.md).
