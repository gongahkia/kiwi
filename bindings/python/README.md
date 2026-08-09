# strok Python bindings

This initial CPython extension is deliberately limited to importing a module
linked against the installed `strok_c_api` shared library and reporting its ABI
version. Renderer and NumPy APIs are added by follow-up issues.

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
