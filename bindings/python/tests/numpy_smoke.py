import os
import sys


if os.name == "nt":
    os.add_dll_directory(os.environ["STROK_LIBRARY_DIR"])

import numpy as np
import strok


def expect(exception_type, callback):
    try:
        callback()
    except exception_type:
        return
    raise SystemExit(f"expected {exception_type.__name__}")


renderer = strok.Renderer(2, 2)

rgb_storage = np.zeros(16, dtype=np.uint8)
rgb = np.ndarray((2, 2, 3), dtype=np.uint8, buffer=rgb_storage, strides=(8, 3, 1))
rgb[0, 1] = (255, 0, 0)
rgb[1, 0] = (0, 255, 0)
rgb[1, 1] = (255, 255, 255)
renderer.render_numpy(rgb)
if renderer.cells().dimensions()[0] <= 0:
    raise SystemExit("strided RGB NumPy render produced no cells")

rgba = np.array(
    [[[0, 0, 255, 255], [255, 255, 0, 255]], [[255, 0, 255, 255], [255, 255, 255, 255]]],
    dtype=np.uint8,
)
renderer.render_numpy(rgba)

depth_storage = np.zeros((2, 3), dtype=np.float64)
depth = depth_storage[:, :2]
depth[:] = ((1.0, 2.0), (3.0, 4.0))
normal_storage = np.zeros((2, 3, 3), dtype=np.float64)
normals = normal_storage[:, :2, :]
normals[:, :, 2] = 1.0
renderer.render_numpy(rgb, depth=depth, normals=normals)
if renderer.cells().cell(0, 0)[0] == "":
    raise SystemExit("rich NumPy render returned an invalid glyph")

expect(ValueError, lambda: renderer.render_numpy(rgb.astype(np.float32)))
expect(ValueError, lambda: renderer.render_numpy(rgb[:, ::-1, :]))
expect(ValueError, lambda: renderer.render_numpy(rgb, depth=np.zeros((1, 2), dtype=np.float64)))
expect(ValueError, lambda: renderer.render_numpy(rgb, normals=np.zeros((2, 2, 2), dtype=np.float64)))

sys.exit(0)
