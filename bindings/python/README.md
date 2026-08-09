# strok Python bindings

The CPython extension links only the installed `strok_c_api` shared library.
It provides `Renderer(columns, rows, cell_aspect=0.5)`, contiguous RGB24
`render_rgb(data, width, height)`, and read-only `CellBuffer` results through
`dimensions()` and `cell(column, row)`.

`render_rgb` accepts a contiguous buffer with exactly `width * height * 3`
bytes and does not retain it. A CellBuffer keeps its renderer alive, but raises
`StaleResultError` after a later successful render replaces that result.
Invalid renderer/image arguments raise `ValueError`; operations after
`Renderer.close()` raise `RuntimeError`. `Renderer.reset()` resets temporal
state while retaining the current CellBuffer result, matching the C ABI.

Build from an installed C ABI prefix:

```sh
STROK_PREFIX=/path/to/strok-prefix python3 -m pip install --no-build-isolation ./bindings/python
```

For a development C ABI build, provide both paths explicitly:

```sh
STROK_INCLUDE_DIR="$PWD/include" \
  STROK_LIBRARY_DIR="$PWD/build/core" \
  python3 -m pip install --no-build-isolation ./bindings/python
```

The extension validates header and library discovery before compiling. On Linux,
the built extension carries the discovered library directory as its runtime
search path. Other platforms use their normal loader conventions.
