import assert from "node:assert/strict";
import { chromium } from "playwright";

const fixtures = parseFixtures(await readStdin());
const browser = await chromium.launch();

try {
  for (const [mode, svg] of fixtures) {
    assert.match(svg, /prefers-reduced-motion/, `${mode}: missing reduced-motion query`);
    assert.match(svg, /kumeyuri-progress-dots/, `${mode}: missing progress dots`);
    await assertReducedMotion(browser, mode, svg);
    await assertNoPreference(browser, mode, svg);
  }
} finally {
  await browser.close();
}

console.log(`reduced-motion ok: ${fixtures.size} SVG fixtures`);

async function assertReducedMotion(browser, mode, svg) {
  const state = await renderState(browser, svg, "reduce");
  assert.equal(state.prefersReducedMotion, true, `${mode}: reduced-motion media query inactive`);
  assert.equal(state.frame0Opacity, "1", `${mode}: first frame is not static under reduced motion`);
  assert.equal(state.frame1Opacity, "0", `${mode}: later frame is visible under reduced motion`);
  assert.equal(state.dotsOpacity, "1", `${mode}: progress dots are hidden under reduced motion`);
  assert.equal(state.frame0Animation, "none", `${mode}: first frame CSS animation still active`);
  assert.equal(state.frame1Animation, "none", `${mode}: later frame CSS animation still active`);
}

async function assertNoPreference(browser, mode, svg) {
  const state = await renderState(browser, svg, "no-preference");
  assert.equal(
    state.prefersReducedMotion,
    false,
    `${mode}: no-preference context matched reduced-motion media query`,
  );
  assert.equal(state.dotsOpacity, "0", `${mode}: progress dots visible without reduced motion`);
}

async function renderState(browser, svg, reducedMotion) {
  const context = await browser.newContext({ reducedMotion });
  const page = await context.newPage();
  try {
    await page.setContent(`<!doctype html><html><body>${svg}</body></html>`, {
      waitUntil: "domcontentloaded",
    });
    await page.waitForSelector("#kumeyuri-progress-dots");
    return await page.evaluate(() => {
      const frame0 = document.querySelector("#frame-0");
      const frame1 = document.querySelector("#frame-1");
      const dots = document.querySelector("#kumeyuri-progress-dots");
      for (const [id, element] of [
        ["frame-0", frame0],
        ["frame-1", frame1],
        ["kumeyuri-progress-dots", dots],
      ]) {
        if (!(element instanceof Element)) {
          throw new Error(`missing #${id}`);
        }
      }
      return {
        prefersReducedMotion: matchMedia("(prefers-reduced-motion: reduce)").matches,
        frame0Opacity: getComputedStyle(frame0).opacity,
        frame1Opacity: getComputedStyle(frame1).opacity,
        dotsOpacity: getComputedStyle(dots).opacity,
        frame0Animation: getComputedStyle(frame0).animationName,
        frame1Animation: getComputedStyle(frame1).animationName,
      };
    });
  } finally {
    await context.close();
  }
}

function parseFixtures(source) {
  const fixtures = new Map();
  let mode = undefined;
  let buffer = [];
  for (const line of source.split("\n")) {
    const nextMode = parseFixtureMarker(line);
    if (nextMode) {
      if (mode) {
        fixtures.set(mode, buffer.join("\n").trim());
      }
      mode = nextMode;
      buffer = [];
    } else if (mode) {
      buffer.push(line);
    }
  }
  if (mode) {
    fixtures.set(mode, buffer.join("\n").trim());
  }
  for (const mode of ["smil", "css"]) {
    if (!fixtures.has(mode)) {
      throw new Error(`missing ${mode} SVG fixture`);
    }
  }
  return fixtures;
}

function parseFixtureMarker(line) {
  const prefix = "--kumeyuri-svg-mode:";
  const suffix = "--";
  if (!line.startsWith(prefix) || !line.endsWith(suffix)) {
    return undefined;
  }
  const mode = line.slice(prefix.length, -suffix.length);
  return mode && Array.from(mode).every((char) => char >= "a" && char <= "z") ? mode : undefined;
}

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}
