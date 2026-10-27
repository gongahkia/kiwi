# Cocoa accessibility text qualification, 2026-10-27

At clean `d99b9bf`, the [external AX test](2026-10-27-cocoa-ax.json) passed on
Intel macOS 15.7.7. It queried a real Kiwi application with controlled raw PTY
output from a separate trusted accessibility client. The application exited
successfully and its PTY child was reaped.

The native change in `e6f31c1` adds checked UTF-16 substring queries, plain
attributed substrings, physical line/index mapping and composed-character ranges.
It rejects out-of-bounds/overflowed requests and ranges splitting surrogate pairs,
and validates the supplied scalar count against the complete native string.
Value, selection and focus notifications now depend on actual property changes.

A [filtered diagnostic query before the change](2026-10-27-cocoa-ax-before.json)
recorded `kAXErrorParameterizedAttributeUnsupported` (-25213) for all five text
query APIs. That early fixture had terminal echo enabled, so its visible text and
selected text were deliberately excluded from the retained diagnostic. The
repeatable test uses a raw PTY and records only synthetic checks and counts.

The passing live test verifies:

- Read-only text-area semantics, UTF-16 character count and visible range.
- Exact emoji and combining substrings, composed ranges for every code unit in
  those clusters, plain attributed text, physical lines and end-of-text.
- Caret range and insertion line after the child's Unicode output.
- Unchanged text, selected text and selected range after external mutation
  requests. AppKit returns transport success for these requests while leaving
  the non-settable properties unchanged; the check verifies actual state.
- No repeated value, selection or focus events during ten unchanged PTY turns.
- New real PTY output producing both value and caret/selection events. The
  retained run observed one value event, one selection event and no focus event.

`make test-cocoa-accessibility` also passes. It exercises the production AppKit
text element and update routine without a visible window, including invalid
UTF-8/counts, oversized text, overflowed ranges, surrogate pairs, combining marks,
ZWJ emoji, empty and trailing lines, changed selected text, and 1,000 unchanged
updates. It runs in `make check`, including both macOS CI architectures. The
native bridge build, existing Cocoa native smoke and eight semantic/projection
Lua tests passed locally. Hosted CI execution is not claimed by these results.

Run the external check with:

```sh
make cocoa-accessibility-smoke
# Or after building the native bridge:
./script/cocoa-accessibility-smoke --report /tmp/kiwi-cocoa-ax.json
```

Existing accessibility-client permission and a graphical session are required.
The fixture raises only its owned window onto the active Space. Earlier probes
could not discover the window while it was outside the active Space; those
attempts were not treated as passes. This visibility setup is test-only and does
not resolve the separate macOS endurance qualification. No accessibility or
Space preference was changed and VoiceOver was not started.

This evidence qualifies the external text-query and notification contract. It
does not qualify VoiceOver speech/navigation, braille, per-character geometry,
real IME, multiple-pane reading, monitor changes, system sleep or daily usability.
