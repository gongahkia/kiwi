import assert from "node:assert/strict";
import { mkdir, readFile } from "node:fs/promises";
import { chromium, webkit } from "playwright";
import AxeBuilder from "@axe-core/playwright";

process.env.BASE_PATH = "/strok/";
const { createServer } = await import("../scripts/serve.mjs");
const server = createServer();
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const base = `http://localhost:${server.address().port}/strok/`;
await mkdir(new URL("../test-results/", import.meta.url), { recursive: true });
const errors = [];
let browser;

async function open(context) {
  const page = await context.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", (request) => {
    if (
      !request.url().startsWith(base) &&
      !request.url().startsWith("blob:") &&
      !request.url().startsWith("data:")
    )
      errors.push(`Unexpected external request: ${request.url()}`);
  });
  await page.goto(base);
  await page.locator("body[data-engine=ready]").waitFor({ timeout: 30000 });
  await page.locator("#output[data-frame]").waitFor({ timeout: 30000 });
  return page;
}

async function changedFrame(page, action) {
  const previous = await page.locator("#output").getAttribute("data-frame");
  await action();
  await page.waitForFunction(
    (id) => document.querySelector("#output").dataset.frame !== id,
    previous,
    { timeout: 15000 },
  );
}

try {
  browser = await chromium.launch({
    headless: true,
    args: [
      "--use-fake-device-for-media-stream",
      "--use-fake-ui-for-media-stream",
    ],
  });
  const desktop = await browser.newContext({
    viewport: { width: 1440, height: 1100 },
    permissions: ["camera"],
    acceptDownloads: true,
  });
  await desktop.addInitScript(() => {
    window.__testStreams = [];
    const original = navigator.mediaDevices.getUserMedia.bind(
      navigator.mediaDevices,
    );
    navigator.mediaDevices.getUserMedia = async (constraints) => {
      const stream = await original(constraints);
      window.__testStreams.push(stream);
      return stream;
    };
  });
  const page = await open(desktop);
  assert.equal(
    await page.locator("#output").getAttribute("data-source"),
    "demo",
  );
  assert.equal(
    await page.evaluate(() => window.__testStreams.length),
    0,
    "camera permission is never requested on load",
  );
  assert.equal(
    await page
      .locator('[data-palette="original"]')
      .getAttribute("aria-pressed"),
    "true",
    "original color is the default look",
  );
  assert.equal(
    (await page.locator(".ascii-wordmark").textContent()).split("\n").length,
    6,
    "ASCII wordmark keeps its six lines",
  );
  assert.equal(await page.title(), "Strok");
  assert.equal(
    await page
      .locator(
        ".site-header, .site-footer, #about, #demo, #pause, .booth-instruction",
      )
      .count(),
    0,
  );
  for (let effect = 0; effect < 6; effect++) {
    await changedFrame(page, () =>
      page.locator(`[data-effect="${effect}"]`).click(),
    );
    assert.equal(
      await page
        .locator(`[data-effect="${effect}"]`)
        .getAttribute("aria-pressed"),
      "true",
    );
    assert.equal(
      await page.locator("#notice").isVisible(),
      false,
      `effect ${effect} rendered without errors`,
    );
  }
  for (const palette of ["paper", "amber", "green", "pink", "original"]) {
    await page.locator(`[data-palette="${palette}"]`).click();
    assert.equal(
      await page
        .locator(`[data-palette="${palette}"]`)
        .getAttribute("aria-pressed"),
      "true",
    );
  }
  await changedFrame(page, () => page.locator("#detail").fill("132"));
  assert.match(await page.locator("#render-label").textContent(), /132 × 50/);
  await changedFrame(page, () => page.locator('[data-effect="0"]').click());
  await page.locator(".advanced > summary").click();
  await changedFrame(page, () => page.locator("#edge").fill("80"));
  await changedFrame(page, () => page.locator("#contrast").fill("25"));
  await changedFrame(page, () => page.locator("#reset").click());
  await page.locator(".advanced > summary").click();
  assert.equal(
    await page.locator('[data-effect="4"]').getAttribute("aria-pressed"),
    "true",
    "reset restores the Blocks default",
  );
  await page.locator("#custom-color").evaluate((input) => {
    input.value = "#ff3344";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  assert.equal(
    await page.locator('[data-palette="custom"]').getAttribute("aria-pressed"),
    "true",
  );
  assert.equal(
    await page.locator("#palette-name").textContent(),
    "Custom #FF3344",
  );
  await page.evaluate(() => {
    window.__printStages = [];
    new MutationObserver(() => {
      const phase = document.body.dataset.printing;
      if (phase) window.__printStages.push(phase);
    }).observe(document.body, {
      attributes: true,
      attributeFilter: ["data-printing"],
    });
  });
  await page.locator("#timer").selectOption("0");
  await page.locator("#shutter").click();
  await page.locator(".photo-card").waitFor();
  assert.equal(await page.locator(".photo-card").count(), 1);
  assert.deepEqual(
    [...new Set(await page.evaluate(() => window.__printStages))],
    ["jitter", "feeding", "deposited", "placing"],
  );
  assert.equal(
    await page.locator(".print-delivery, .print-flight, .delivering").count(),
    0,
    "delivery animation cleans up",
  );
  assert.equal(
    await page.locator("#notice").isVisible(),
    false,
    "capture has no success-copy banner",
  );

  assert.ok(
    await page.locator(".photo-card img").evaluate(async (img) => {
      await img.decode();
      const c = document.createElement("canvas");
      c.width = img.naturalWidth;
      c.height = img.naturalHeight;
      const ctx = c.getContext("2d");
      ctx.drawImage(img, 0, 0);
      const data = ctx.getImageData(0, 0, c.width, c.height).data;
      for (let i = 0; i < data.length; i += 4)
        if (
          data[i] > 80 &&
          data[i] > data[i + 1] * 1.5 &&
          data[i] > data[i + 2] * 1.5
        )
          return true;
      return false;
    }),
    "custom ink is included in the exported PNG",
  );
  const downloadEvent = page.waitForEvent("download");
  await page.getByRole("link", { name: "Save photo 1 as PNG" }).click();
  const download = await downloadEvent;
  assert.match(download.suggestedFilename(), /strok-photo-001\.png/);
  const png = await readFile(await download.path());
  assert.equal(png.subarray(1, 4).toString(), "PNG");
  assert.equal(
    png.readUInt32BE(16),
    1200,
    "PNG is redrawn at export resolution",
  );
  const textDownloadEvent = page.waitForEvent("download");
  await page.getByRole("link", { name: "Save photo 1 as text" }).click();
  const textDownload = await textDownloadEvent;
  assert.match(textDownload.suggestedFilename(), /\.txt$/);
  const text = await readFile(await textDownload.path(), "utf8");
  assert.equal(text.split("\n").length, 54);
  assert.ok(text.split("\n").every((line) => [...line].length === 144));
  for (const count of [2, 3, 4]) {
    await page.locator("#capture-format").click();
    assert.equal(
      await page.locator("#format-label").textContent(),
      `Strip ×${count}`,
    );
    await page.locator("#shutter").click();
    await page.waitForFunction(
      (n) => document.querySelectorAll(".photo-card").length === n,
      count,
      { timeout: 20000 },
    );
    assert.match(
      await page.locator(".photo-card img").first().getAttribute("alt"),
      new RegExp(`${count}-photo strip`),
    );
    const image = page.locator(".photo-card img").first();
    await image.evaluate((img) => img.decode());
    const dimensions = await image.evaluate((img) => ({
      w: img.naturalWidth,
      h: img.naturalHeight,
    }));
    assert.equal(dimensions.w, 720);
    assert.equal(
      dimensions.h,
      29 + 526 * count + 72,
      "strip has the requested number of full frames",
    );
  }
  await page.locator("#capture-format").click();
  assert.equal(await page.locator("#format-label").textContent(), "Single");
  await page.locator("#timer").selectOption("3");
  await page.locator("#shutter").click();
  await page.locator("#countdown").waitFor();
  await page.locator("#shutter").click();
  await page.waitForFunction(
    () => document.querySelector("#shutter-label").textContent === "Snap a pic",
  );
  assert.equal(
    await page.locator(".photo-card").count(),
    4,
    "cancel does not create a photo",
  );
  await page.locator("#camera").click();
  await page.waitForFunction(
    () => document.querySelector("#output").dataset.source === "camera",
  );
  assert.ok(
    await page.evaluate(() =>
      window.__testStreams.some((stream) =>
        stream.getVideoTracks().some((track) => track.readyState === "live"),
      ),
    ),
  );
  await changedFrame(page, () => page.locator("#mirror").uncheck());
  await page.locator("#switch-camera").click();
  await page.waitForFunction(
    () =>
      window.__testStreams.length === 2 &&
      document.querySelector("#output").dataset.source === "camera",
  );
  assert.ok(
    await page.evaluate(() =>
      window.__testStreams[0]
        .getTracks()
        .every((track) => track.readyState === "ended"),
    ),
    "switch releases old camera",
  );
  await page.locator("#camera").click();
  assert.ok(
    await page.evaluate(() =>
      window.__testStreams.every((stream) =>
        stream.getTracks().every((track) => track.readyState === "ended"),
      ),
    ),
    "stop releases all tracks",
  );

  const pngBuffer = Buffer.from(
    await page.evaluate(() => {
      const canvas = document.createElement("canvas");
      canvas.width = 240;
      canvas.height = 320;
      const ctx = canvas.getContext("2d");
      ctx.fillStyle = "#db825b";
      ctx.fillRect(0, 0, 240, 320);
      ctx.fillStyle = "#e8dfa2";
      ctx.beginPath();
      ctx.arc(120, 145, 75, 0, Math.PI * 2);
      ctx.fill();
      return canvas.toDataURL("image/png").split(",")[1];
    }),
    "base64",
  );
  await page.locator("#file").setInputFiles({
    name: "portrait.png",
    mimeType: "image/png",
    buffer: pngBuffer,
  });
  await page.waitForFunction(
    () => document.querySelector("#output").dataset.source === "photo",
  );
  await page.locator("#file").setInputFiles({
    name: "broken.png",
    mimeType: "image/png",
    buffer: Buffer.from("not an image"),
  });
  await page.waitForFunction(() =>
    document.querySelector("#notice").textContent.includes("couldn’t open"),
  );
  assert.equal(
    await page.locator("#output").getAttribute("data-source"),
    "photo",
    "bad upload preserves the working source",
  );
  await page.locator("#clear-photos").click();
  assert.equal(await page.locator("#photos").isVisible(), false);
  await page.screenshot({
    path: new URL("../test-results/desktop.png", import.meta.url).pathname,
    fullPage: true,
  });
  const accessibility = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  assert.deepEqual(
    accessibility.violations.map((v) => ({
      id: v.id,
      nodes: v.nodes.map((n) => n.target),
    })),
    [],
    "desktop accessibility",
  );
  console.log(
    "PASS Chromium: all effects, palettes, density, advanced controls, capture, strip, cancellation, downloads, fake camera, flip, release, upload, and accessibility",
  );
  await desktop.close();

  const interrupted = await browser.newContext();
  const interruptedPage = await open(interrupted);
  await interruptedPage.locator("#timer").selectOption("0");
  await interruptedPage.locator("#shutter").click();
  await interruptedPage.locator("body[data-printing=feeding]").waitFor();
  await interruptedPage.keyboard.press("Escape");
  await interruptedPage.locator(".photo-card").waitFor();
  await interruptedPage.waitForFunction(() => !document.body.dataset.printing);
  assert.equal(
    await interruptedPage.locator(".photo-card").count(),
    1,
    "interrupting the print keeps the saved capture",
  );
  assert.equal(
    await interruptedPage.locator(".print-delivery, .print-flight").count(),
    0,
  );
  assert.equal(
    await interruptedPage.locator("#gallery").evaluate((el) => el.inert),
    false,
  );
  await interrupted.close();
  const denied = await browser.newContext();
  await denied.addInitScript(() => {
    navigator.mediaDevices.getUserMedia = async () => {
      throw new DOMException("Denied", "NotAllowedError");
    };
  });
  const deniedPage = await open(denied);
  await deniedPage.locator("#camera").click();
  await deniedPage.waitForFunction(() =>
    document.querySelector("#notice").textContent.includes("permission"),
  );
  assert.equal(
    await deniedPage.locator("#output").getAttribute("data-source"),
    "demo",
  );
  await denied.close();

  const lateCamera = await browser.newContext({ permissions: ["camera"] });
  await lateCamera.addInitScript(() => {
    window.__testStreams = [];
    const original = navigator.mediaDevices.getUserMedia.bind(
      navigator.mediaDevices,
    );
    navigator.mediaDevices.getUserMedia = async (constraints) => {
      const stream = await original(constraints);
      window.__testStreams.push(stream);
      await new Promise((resolve) => setTimeout(resolve, 800));
      return stream;
    };
  });
  const latePage = await open(lateCamera);
  await latePage.locator("#camera").click();
  await latePage.locator("#file").setInputFiles({
    name: "portrait.png",
    mimeType: "image/png",
    buffer: pngBuffer,
  });
  await latePage.waitForFunction(
    () =>
      window.__testStreams.length > 0 &&
      window.__testStreams.every((stream) =>
        stream.getTracks().every((track) => track.readyState === "ended"),
      ),
  );
  assert.equal(
    await latePage.locator("#output").getAttribute("data-source"),
    "photo",
    "late camera approval cannot replace a newer source",
  );
  await lateCamera.close();

  const failure = await browser.newContext();
  const failurePage = await failure.newPage();
  await failurePage.route("**/*.wasm", (route) => route.abort());
  await failurePage.goto(base);
  await failurePage
    .locator("body[data-engine=error]")
    .waitFor({ timeout: 15000 });
  assert.equal(
    await failurePage
      .getByRole("button", { name: "Reload the booth" })
      .isVisible(),
    true,
  );
  assert.equal(await failurePage.locator("#camera").isDisabled(), true);
  await failure.close();
  console.log("PASS camera-denied and missing-WebAssembly recovery");

  for (const [width, height] of [
    [320, 568],
    [390, 844],
    [740, 390],
    [768, 844],
  ]) {
    const context = await browser.newContext({
      viewport: { width, height },
      isMobile: true,
      hasTouch: true,
      deviceScaleFactor: 2,
      reducedMotion: "reduce",
    });
    const mobile = await open(context);
    assert.ok(
      await mobile.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
      `no overflow at ${width}px`,
    );
    if (width < 760) {
      assert.equal(
        await mobile.locator(".source-title").isVisible(),
        true,
        "step into the booth stays visible on mobile",
      );
      assert.equal(
        await mobile.locator("#capture-format svg").isVisible(),
        true,
        "strip artwork stays visible on mobile",
      );
      if (height < width) {
        assert.ok(
          await mobile.evaluate(
            () =>
              document.querySelector("#viewfinder").getBoundingClientRect()
                .bottom <=
              document.querySelector(".capture-bar").getBoundingClientRect()
                .top,
          ),
          "landscape preview fits above the shutter dock on entry",
        );
      }
      for (const selector of [".effect", ".palette", "#fullscreen", "#timer"]) {
        const r = await mobile.locator(selector).first().boundingBox();
        assert.ok(r.height >= 44, `${selector} has a mobile touch target`);
      }
      await mobile.locator(".detail-field").scrollIntoViewIfNeeded();
      assert.ok(
        await mobile.locator("#shutter").evaluate((el) => {
          const r = el.getBoundingClientRect();
          return r.top >= 0 && r.bottom <= innerHeight;
        }),
        "shutter remains available while editing below the preview",
      );
      assert.ok(
        await mobile.evaluate(() =>
          Boolean(
            document
              .querySelector(".viewfinder-column")
              .compareDocumentPosition(
                document.querySelector(".effect-field"),
              ) & Node.DOCUMENT_POSITION_FOLLOWING,
          ),
        ),
        "mobile DOM order follows the visual order",
      );
      await mobile.locator("#fullscreen").evaluate((el) => {
        el.closest(".viewfinder").requestFullscreen = undefined;
      });
      await mobile.locator("#fullscreen").click();
      assert.equal(await mobile.locator(".viewfinder.expanded").count(), 1);
      const expanded = await mobile.locator("#viewfinder").boundingBox();
      assert.equal(Math.round(expanded.width), width);
      await mobile.locator("#fullscreen").click();
      assert.equal(await mobile.locator(".viewfinder.expanded").count(), 0);
      if (width === 390) {
        await mobile.locator("#capture-format").click();
        await mobile.locator("#timer").selectOption("3");
        await mobile.locator("#shutter").click();
        await mobile.locator("#countdown").waitFor();
        assert.equal(
          await mobile.locator("#capture-progress").textContent(),
          "Photo 1 of 2",
        );
        await mobile.locator("#shutter").click();
        await mobile.waitForFunction(
          () =>
            document.querySelector("#shutter-label").textContent ===
            "Snap a pic",
        );
        assert.equal(await mobile.locator(".photo-card").count(), 0);
        for (let i = 0; i < 3; i++)
          await mobile.locator("#capture-format").click();
      }
    }
    await mobile.locator("#timer").selectOption("0");
    await mobile.locator("#shutter").click();
    await mobile.locator(".photo-card").waitFor();
    assert.equal(
      await mobile.locator(".print-delivery, .print-flight").count(),
      0,
      "reduced motion skips the printer animation",
    );

    if (width < 760) {
      assert.equal(
        await mobile
          .locator("#gallery a")
          .first()
          .evaluate((el) => el === document.activeElement),
        true,
        "capture focuses the new PNG download",
      );
      assert.ok(
        await mobile
          .locator("#photos")
          .evaluate(
            (el) =>
              el.getBoundingClientRect().top >= 0 &&
              el.getBoundingClientRect().top < innerHeight,
          ),
        "capture brings the contact sheet into view",
      );
    }

    await mobile.screenshot({
      path: new URL(`../test-results/mobile-${width}.png`, import.meta.url)
        .pathname,
      fullPage: true,
    });
    const result = await new AxeBuilder({ page: mobile })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    assert.deepEqual(
      result.violations.map((v) => v.id),
      [],
      `accessibility at ${width}px`,
    );
    await context.close();
  }
  console.log(
    "PASS 320px / 390px / 740px landscape / 768px layouts, reduced motion, photo capture, and accessibility",
  );
  await browser.close();
  browser = null;

  browser = await webkit.launch({
    headless: true,
    executablePath: process.env.WEBKIT_EXECUTABLE_PATH || undefined,
  });
  const safariMotion = await browser.newContext({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    reducedMotion: "no-preference",
  });
  const printPage = await open(safariMotion);
  await printPage.locator("#timer").selectOption("0");
  await printPage.locator("#shutter").click();
  await printPage.locator("body[data-printing=feeding]").waitFor();
  await printPage.locator(".photo-card").waitFor();
  assert.equal(
    await printPage.locator(".print-delivery, .print-flight").count(),
    0,
    "WebKit finishes the receipt delivery",
  );
  await safariMotion.close();
  const safari = await browser.newContext({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
    reducedMotion: "reduce",
  });
  const safariPage = await open(safari);
  await changedFrame(safariPage, () =>
    safariPage.locator('[data-effect="3"]').click(),
  );
  await safariPage.locator("#timer").selectOption("0");
  await safariPage.locator("#shutter").click();
  await safariPage.locator(".photo-card").waitFor();
  assert.ok(
    await safariPage.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  );
  await safariPage.screenshot({
    path: new URL("../test-results/webkit-mobile.png", import.meta.url)
      .pathname,
    fullPage: true,
  });
  console.log(
    "PASS WebKit mobile: native renderer, Braille, photo capture, and layout",
  );
  assert.deepEqual(
    errors,
    [],
    "no uncaught application errors or remote asset requests",
  );
} finally {
  await browser?.close();
  await new Promise((resolve) => server.close(resolve));
}
