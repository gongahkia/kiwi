# Combined application workflows, 2026-10-26

Implementation: `a82c51f`. These are real PTY/application/encoder/parser/replay
checks, not native keyboard, visual rendering or network-latency qualification.

| Environment | Result | Report |
| --- | --- | --- |
| Linux x86_64, Ubuntu 24.04 container | All 11 local cases passed, including fish, both editors, tmux, less, top and the two combined workflows | [Local](2026-10-26-combined-linux.json) |
| Same Linux environment, isolated OpenSSH server | All six cases passed, including combined direct and tmux workflows | [SSH](2026-10-26-combined-ssh-linux.json) |
| Intel macOS workstation | Ten local cases passed; fish failed because the executable was not installed. The complete default suite is therefore not a pass on this machine | [Local](2026-10-26-combined-macos.json) |
| Same macOS environment, isolated OpenSSH server | All six cases passed | [SSH](2026-10-26-combined-ssh-macos.json) |

macOS reports were collected from the implementation working tree before the
code commit; they explicitly say dirty. Linux used an archive of `a82c51f` with
`BUILD_REVISION`, without a Git working-tree cleanliness assertion. Reports retain
program versions, parser diagnostics, byte counts and case-level checkpoints.

The combined local case keeps Bash alive through Neovim → less → Vim → less.
The tmux and two SSH combined cases keep a shell alive through Neovim → less.
Editors save exact wide/combining Unicode text, resize through SIGWINCH, edit
using navigation/backspace and save again. Pagers search, resize and page.
Between applications, the test verifies screen selection and input/reporting
modes, executes pasted shell text, then runs a child-side cursor/device-query
handshake. Direct and SSH cases also push/query Kitty flags 1/2/8/16, accept
encoded committed text and pop the mode. tmux exercises legacy text instead.

Each passing capture was replayed as whole chunks, individual bytes and eight
seeded chunkings, and compared with the live final state. No unexpected parser
errors or controls were permitted. The known Vim negative probes remain narrowly
scoped to the active Vim process. Test fixture failures found during development
(accepting an echoed readiness string, and comparing backing-screen identities
across resize) were fixed before these runs.

`make check` also passed on macOS: 663 Lua tests in 131 suites, 18 PTY tests,
128 seeded fuzz cases plus corpus, readiness/file/process-metrics checks,
interactive benchmark/budget harnesses, regex oracle, terminfo and source checks.
Linux/macOS CI includes the new cases; remote CI execution is not asserted here.
Physical desktop input, representative remote networks and remote operating
systems remain separate qualification work.
