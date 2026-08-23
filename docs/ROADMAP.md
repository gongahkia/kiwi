# Kiwi roadmap

The daily-driver compatibility ledger is Kiwi's release contract. This roadmap
records the work sequence toward a Ghostty-class native terminal without
relabeling already implemented work as future milestones.

## Foundations — complete

M0 through M2.5 delivered the renderer laboratory, PTY-backed terminal kernel,
measured pipeline, Unicode 17 text foundation, and write-path hardening.

The former M3–M7 scope is substantially implemented: semantic render passes
and a bounded extension API, text-backend experiments, selection/search/links,
shell integration and command regions, configuration/reload, bounded Kitty
PNG/APNG/GIF graphics, replay/diagnostics, reproducible local artifacts, and
Linux/macOS platform seams. Their remaining gaps are tracked below rather than
declared complete.

## R1 — reliable release baseline

- Keep `make native`, `make test`, `make check`, and `make release-check`
  runnable from a clean supported host.
- Publish MIT-licensed, source-backed Linux x86_64 and macOS arm64 artifacts
  from version-matched Git tags.
- Retain explicit platform, signing, and manual-qualification limits.

## R2 — native hosts

- The internal host facade and host-owned WGPU surface contract are complete.
- GTK4's bounded Wayland/X11 rendering and PTY runs pass. Its Wayland WGPU
  presenter owns a child surface beneath the GTK toplevel and uses
  `wp_viewporter` for logical-size presentation. GTK IME and accessible-text
  callback bridges have bounded smoke coverage. Its `GMenu` opens a searchable
  dialog over the same configuration-augmented bounded product-action catalogue
  as Cocoa; its
  graphical palette smoke is not yet local qualification evidence. Interactive desktop
  qualification, including real IME, fractional scale, clipboard, and Orca,
  remains outstanding.
- GTK-native tabs are experimental, not deferred: the opt-in
  `KIWI_GTK_NATIVE_TABS=1` GL route renders inside a GTK widget and owns an
  `AdwTabView` page per independent VT/PTY/session. It proves bounded New
  Tab/Next Tab routing, including background PTY draining without hidden-page
  presentation, but it is not a supported host-tab feature. The opaque
  compositor acquire/encode/present-or-abort lifecycle is implemented and
  live-smoked through Cocoa/Metal. The next core slice,
  `prepared_frame`, now produces WGPU-free terminal cells, shaped glyphs,
  glyph-atlas updates, overlays, and frame uniforms with explicit retry/commit
  ownership. `prepared_images` now also produces renderer-neutral decoded
  Kitty image data and visible placements; GPU residency remains WGPU-specific.
  The GTK host now has an opt-in, single-terminal GtkGLArea/OpenGL adapter:
  `KIWI_GTK_PRESENTER=gl make gtk-run` feeds a real VT/PTy/shaping frame into
  background, overlays, alpha-atlas glyph, command-region, and cursor passes.
  Its initial/resize/retry grid snapshots are complete, while normal terminal
  updates retain a bounded native mirror and upload only dirty ranges and
  changed glyph/atlas resources. Workspace state, Kitty images, colour
  management, pacing/recovery, detach/transfer, manager host-tab ownership,
  and graphical Linux evidence remain open. The prototype now has a bounded
  non-final-page close transaction; the next approved slice is the group-owner
  lifecycle and its detach/transfer gates; see [ADR
  0041](adr/0041-embedded-gtk-presentation.md). Do not
  advertise the prototype as supported GTK tab chrome before those gates pass.
- The GLFW Cocoa route already has bounded AppKit-owned `New Tab`/`Next Tab`
  containers, explicitly separate native windows, menu, searchable command
  palette, action-only AppleScript bridge, text-input, accessibility, and
  pasteboard bridges. It is not an AppKit host: GLFW still owns the terminal
  surface and split content, and replacing that custom split workspace remains
  a separate, gated product decision after GTK4 desktop qualification.
- Keep terminal state, PTY policy, and renderer ownership free of platform UI
  handles. See [NATIVE_HOSTS.md](NATIVE_HOSTS.md).

## R3 — daily-driver desktop contract

- Qualify tabs, splits, windows, recovery, clipboard, IME, accessibility,
  configuration, themes, and system appearance on every claimed platform.
- Replace fixed GLFW workspace chrome with native host behavior only after the
  matching host passes the compatibility ledger.

## R4 — application-led VT compatibility

- Triage real application failures through the daily-driver corpus.
- Add deterministic fixtures, PTY/input coverage, native evidence, and an
  explicit conformance entry before advertising a capability.
- Widen terminfo only after the complete behavior is verified. See
  [DAILY_DRIVER_CORPUS.md](DAILY_DRIVER_CORPUS.md).

## R5 — measured capability expansion

- Evaluate bidi/line breaking, colour emoji, atlas evolution, graphics
  protocols, and richer input only from demonstrated daily-driver demand.
- Preserve resource bounds, host security policy, and replayable evidence.
