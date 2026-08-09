# ADR 0002: GLFW over SDL3 for M0

## Decision

Use GLFW 3.4 for the M0 native window and input layer.

## Evaluation

GLFW has a small stable C API that is straightforward to declare in LuaJIT FFI, native Wayland/X11 handle access for wgpu surfaces, framebuffer-size and content-scale APIs, keyboard events, and established macOS/Windows support. Fedora 43 supplied `glfw-devel` and working pkg-config metadata in the target environment. SDL3's runtime was installed, but its development metadata was absent.

GLFW's native-handle surface chain still needs a tiny compiled bridge because wgpu's Wayland/X11 tagged C structures must match the pinned header exactly. This bridge is smaller and less brittle than reproducing platform-specific native structs in Lua. SDL3 would not remove that wgpu surface-chain problem and would add an unavailable development dependency on the observed Fedora host.

## Consequences

M0 supports GLFW's Wayland and X11 platforms on Linux. The platform interface remains narrow enough to substitute SDL3 or another library later.
