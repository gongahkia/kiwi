import assert from "node:assert/strict";
import test from "node:test";

import {
  AnsiScreen,
  defineContourttyPlayer,
  parseCast,
  parseRecording,
  recordingToHtml,
} from "../dist/contourtty-embed.js";

test("module imports without a DOM", () => {
  assert.equal(defineContourttyPlayer(), undefined);
});

test("ANSI screen handles SGR, cursor movement, and clearing", () => {
  const screen = new AnsiScreen(4, 2);
  screen.write("A\x1b[31mB\x1b[0m\r\nC\x1b[1;1HZ\x1b[2KQ");
  assert.equal(screen.toHtml(), " Q\nC");
});

test("ANSI renderer emits scoped HTML spans for color runs", () => {
  const screen = new AnsiScreen(3, 1);
  screen.write("A\x1b[38;2;1;2;3mB");
  assert.equal(screen.toHtml(), "A<span style=\"color:#010203\">B</span>");
});

test("asciinema v2 cast parses and renders by timestamp", () => {
  const cast = [
    "{\"version\":2,\"width\":4,\"height\":2}",
    "[0.000,\"o\",\"A\"]",
    "[0.500,\"o\",\"B\"]",
    "[1.000,\"i\",\"ignored input\"]",
  ].join("\n");
  const recording = parseCast(cast);
  assert.equal(recording.cols, 4);
  assert.equal(recording.rows, 2);
  assert.equal(recording.duration, 0.5);
  assert.equal(recordingToHtml(recording, 0.25), "A\n");
  assert.equal(recordingToHtml(recording, 0.50), "AB\n");
});

test("auto parser falls back to raw ANSI", () => {
  const recording = parseRecording("x\x1b[32my", { cols: 3, rows: 1 });
  assert.equal(recording.format, "ansi");
  assert.equal(recordingToHtml(recording, 0), "x<span style=\"color:#008000\">y</span>");
});
