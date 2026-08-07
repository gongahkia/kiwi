# Milestone 15 evidence and next-slice decision

This record distinguishes local implementation evidence from evidence that
requires other operating systems or participants. It contains no participant
data.

## Measured local evidence

On 2026-08-07 at commit `88f20bd` plus the Milestone 15 working changes,
`make benchmark` ran on an Apple M3, arm64 macOS 26.5.2, CPython 3.12.12 using
the checked-in `typed_core.dtr` policy and minimal kernel fixture:

| Path | Operations | Nanoseconds per operation |
| --- | ---: | ---: |
| Full compiler pipeline | 100 | 360,902.920 |
| VM entry evaluation | 100 | 45,425.840 |
| Authoritative tick | 6,000 | 4,817,639.666 |
| Retained trace capture | 100 | 43,955.000 |
| Replay package encode/decode | 100 | 513,141.670 |

These are host-specific informational measurements, not portable performance
guarantees or CI limits. The packaging prototype is recorded separately in
`PACKAGING.md`: it produced and launched a 40 MiB arm64 macOS application
bundle with the Terminal sources and assets embedded.

## Implementation evidence

- Policy projects now have headless path-confinement, schema, source, entry,
  and parameters validation, with preserved DSL source diagnostics.
- Settings, local codex progress, replay reads, and trace queries recover only
  from a complete adjacent backup that passes ordinary validation; failures
  remain concise structured output rather than raw tracebacks.
- The manual Terminal protocol in `TESTING.md` directly tests the PRD's core
  claim: explain the threshold, identify the injury's source, change `1m` to
  `0m`, and explain the replay comparison.
- Final local verification passed: `make doctor`, `make check`, and
  `git diff --check`; `make check` completed 806 tests in 33.16 seconds.

## Evidence still unavailable

- No observed usability sessions with unfamiliar programmers have been run, so
  no language-comprehension or causal-explanation result can be claimed.
- No Linux benchmark or package build has been measured.
- No Windows benchmark or package build has been measured.
- The macOS prototype is ad-hoc signed only; it is not a notarized release.

## Decision

The next product slice is an adoption-evidence slice, not another language,
mission, or rendering expansion. Run the existing observer-led Terminal drill
with unfamiliar programmers, record consented task completion and confusion
outside the repository, and use the results to prioritize a single
comprehension or causal-explanation repair. Do not claim broader platform
support until the separate Linux and Windows evidence gaps close.

This follows the PRD's vertical-slice acceptance rule: an unfamiliar programmer
must trace a consequence to code, alter the policy, and observe a deterministic
change before more content or polish is justified.
