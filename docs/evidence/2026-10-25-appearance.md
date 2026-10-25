# Tabs, transparency and shaders: local evidence

Production implementation: `8c585f7`, `a6c8581`, `1b3721f`.
Tests were run on the existing Intel macOS development machine and the isolated
Ubuntu 24.04 x86_64 qualification container. No physical Linux desktop or Windows
qualification is claimed.

| Check | Result |
| --- | --- |
| macOS `make check test-core` | 544 Lua tests, 17 PTY tests, 316 core tests; fuzz, native watcher/process checks, CLI and syntax checks passed |
| Linux `make test test-core` | 544 Lua tests and 316 core tests passed |
| Native Cocoa tab bridge | Selecting tabs 1 and 2 matched AppKit's selected window; missing tab 9 retained the selection |
| Cocoa palette smoke | Default Command+Shift+P resolved to the palette; selecting New Tab reached the live native tab controller |
| macOS interaction smoke | Passed pane, font and history interactions, including configuration rollback |
| macOS appearance GPU readback | Passed background alpha 1/0.5/0/1, opaque text, two split panes, gutters, custom effect output, rejected shader recovery, resize and both examples |
| macOS truecolour GPU readback | Passed; more than 4.6 million sampled pixels matched RGB 18,171,52 within the existing tolerance |
| macOS and Linux live configuration smoke | Passed config/theme/shader file watching, invalid/missing shader rollback, recovery, effect removal and retained PTY scrollback |
| Linux shader GPU readback | Passed opaque-only mode on Xvfb with Mesa software Vulkan: split panes, effect output, invalid shader recovery, resize and examples |

The Linux container used private GLFW 3.4, Mesa's Lavapipe ICD and Xvfb. Adding
xcompmgr did **not** make GLFW's Vulkan window transparent: the framebuffer
attribute stayed false, and surface alpha capabilities were opaque/inherit.
GLFW 3.4 selects the default X11 visual for `GLFW_NO_API`. Kiwi rejects requested
transparency on this path instead of silently ignoring it. An alpha-capable X11
window path remains work to do; Wayland also needs desktop qualification.

The full `make cocoa-smoke` target passed the native bridge, window/session move,
layout restoration, toolbar, proxy URL and palette portions, then stopped at
Apple-event bundle construction because `sdp` requires full Xcode and this
machine has Command Line Tools only. This is not a complete bundle/release pass.
The direct interaction and palette checks were run successfully afterwards.

The CI definitions now exercise macOS appearance readback and Linux opaque shader
readback/reload. Those workflow changes have not been executed by GitHub here.
