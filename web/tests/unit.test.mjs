import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULTS,
  normalizeOptions,
  rendererOptions,
  cellsToText,
  cameraErrorMessage,
  fitRect,
} from "../src/model.js";

test("browser configuration bounds native work and keeps the grid at 4:3", () => {
  assert.deepEqual(normalizeOptions(), DEFAULTS);
  const normalized = normalizeOptions({
    columns: Infinity,
    effect: -5,
    edge: 500,
    contrast: NaN,
    palette: "__proto__",
  });
  assert.equal(normalized.columns, 96);
  assert.equal(normalized.effect, 0);
  assert.equal(normalized.edge, 100);
  assert.equal(normalized.contrast, 0);
  assert.equal(normalized.palette, "original");
  for (const columns of [48, 60, 96, 132, 144]) {
    const config = rendererOptions({ columns });
    assert.ok(config.columns <= 144 && config.rows <= 54);
    assert.ok(config.edge > 0 && config.edge < 1);
    assert.ok(Math.abs(config.columns / (config.rows * 2) - 4 / 3) < 0.06);
  }
});

test("text export preserves Unicode code points and row boundaries", () => {
  const cells = new Uint32Array([
    0x41, 0, 0, 0x2801, 0, 0, 0x2580, 0, 0, 0x20, 0, 0,
  ]);
  assert.equal(cellsToText(cells, 2, 2), "A⠁\n▀ ");
});

test("source fitting contains uploads and covers the camera without stretching", () => {
  assert.deepEqual(fitRect(100, 200, 400, 300), {
    x: 125,
    y: 0,
    width: 150,
    height: 300,
  });
  assert.deepEqual(fitRect(100, 200, 400, 300, true), {
    x: 0,
    y: -250,
    width: 400,
    height: 800,
  });
  assert.throws(() => fitRect(0, 200, 400, 300), RangeError);
});

test("camera failures explain actionable recovery", () => {
  assert.match(cameraErrorMessage({ name: "NotAllowedError" }), /permission/);
  assert.match(cameraErrorMessage({ name: "NotFoundError" }), /No camera/);
  assert.match(cameraErrorMessage({ name: "NotReadableError" }), /busy/);
  assert.match(cameraErrorMessage({ name: "SecurityError" }), /HTTPS/);
  assert.match(cameraErrorMessage({}), /upload a photo/);
});
