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
  callback bridges have bounded smoke coverage. Interactive desktop
  qualification, including real IME, fractional scale, clipboard, and Orca,
  remains outstanding.
- The GLFW Cocoa route already has bounded AppKit menu, text-input,
  accessibility, and pasteboard bridges. It is not an AppKit host: replacing
  GLFW-owned windows and custom workspace chrome remains a separate, gated
  product decision after GTK4 desktop qualification.
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
