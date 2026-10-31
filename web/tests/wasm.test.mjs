import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import createStrok from "../../build/web/wasm/strok.mjs";

const wasmBinary = await readFile(
  new URL("../../build/web/wasm/strok.wasm", import.meta.url),
);
const module = await createStrok({ wasmBinary });
const width = 64,
  height = 48,
  length = width * height * 4;
const input = module._malloc(length);
const rgba = new Uint8Array(length);
for (let y = 0; y < height; y++)
  for (let x = 0; x < width; x++) {
    const i = (y * width + x) * 4;
    rgba.set([x * 4, y * 5, (x + y) % 2 ? 240 : 50, 255], i);
  }
module.HEAPU8.set(rgba, input);
const error = () => module.UTF8ToString(module._strok_web_error());
function cells(handle) {
  const pointer = module._strok_web_cells(handle),
    count = module._strok_web_cell_count(handle);
  return module.HEAPU32.slice(pointer >>> 2, (pointer >>> 2) + count * 3);
}

test("all browser effects render through the actual C++ core and embedded assets", () => {
  for (let effect = 0; effect <= 6; effect++) {
    const handle = module._strok_web_create(48, 18, effect, 0.08, 0, 1);
    assert.ok(handle, `effect ${effect}: ${error()}`);
    try {
      assert.equal(
        module._strok_web_render(handle, input, width, height, length),
        1,
        error(),
      );
      assert.equal(module._strok_web_cell_count(handle), 48 * 18);
      const first = cells(handle);
      assert.ok(first.some((value, index) => index % 3 === 0 && value !== 32));
      assert.ok(
        first.every((value, index) =>
          index % 3 === 0 ? value <= 0x10ffff : value <= 0xffffff,
        ),
      );
      assert.equal(
        module._strok_web_render(handle, input, width, height, length),
        1,
        error(),
      );
      module._strok_web_reset(handle);
      assert.equal(
        module._strok_web_render(handle, input, width, height, length),
        1,
        error(),
      );
      assert.deepEqual(
        cells(handle),
        first,
        "reset reproduces first-frame reconstruction",
      );
    } finally {
      module._strok_web_destroy(handle);
    }
  }
});

test("invalid configurations and image layouts fail without poisoning the renderer", () => {
  assert.equal(module._strok_web_create(0, 18, 0, 0.08, 0, 0), 0);
  assert.match(error(), /configuration/);
  assert.equal(module._strok_web_create(48, 18, 0, NaN, 0, 0), 0);
  const handle = module._strok_web_create(48, 18, 1, 0.08, 0, 0);
  try {
    assert.equal(
      module._strok_web_render(handle, input, width, height, length - 1),
      0,
    );
    assert.match(error(), /RGBA/);
    assert.equal(
      module._strok_web_render(handle, input, 2048, height, length),
      0,
    );
    assert.equal(
      module._strok_web_render(handle, input, width, height, length),
      1,
    );
    assert.equal(error(), "");
  } finally {
    module._strok_web_destroy(handle);
  }
});

test("repeated renderer creation and destruction preserves runtime usability", () => {
  for (let index = 0; index < 24; index++) {
    const handle = module._strok_web_create(48, 18, index % 6, 0.1, 0, 0);
    assert.ok(handle, error());
    assert.equal(
      module._strok_web_render(handle, input, width, height, length),
      1,
      error(),
    );
    module._strok_web_destroy(handle);
  }
  module._free(input);
});
