import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join } from "node:path";
import { inflateSync } from "node:zlib";
import { chromium, devices, firefox, webkit } from "playwright";

const root = process.cwd();
const updateScreenshots = process.env.KUMEYURI_UPDATE_WEB_COMPONENT_SCREENSHOTS === "1";
const componentModule = await readFile(join(root, "packages/kumeyuri/dist/index.js"), "utf8");
const targets = [
  { name: "chromium", browserType: chromium },
  { name: "firefox", browserType: firefox },
  { name: "webkit", browserType: webkit },
  { name: "mobile-chromium", browserType: chromium, contextOptions: devices["Pixel 7"] },
  { name: "mobile-webkit", browserType: webkit, contextOptions: devices["iPhone 15"] },
];

const { server, url } = await serve();
const failures = [];

try {
  for (const target of targets) {
    try {
      await runTarget(target, url);
      console.log(`ok ${target.name}`);
    } catch (error) {
      failures.push({ target: target.name, error });
      console.error(`not ok ${target.name}: ${error.message}`);
    }
  }
} finally {
  await closeServer(server);
}

if (failures.length > 0) {
  throw new Error(
    failures
      .map(({ target, error }) => `${target}: ${error.stack ?? error.message}`)
      .join("\n\n"),
  );
}

async function runTarget(target, baseUrl) {
  const browser = await target.browserType.launch();
  const context = await browser.newContext(target.contextOptions ?? {});
  const page = await context.newPage();
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(error));

  try {
    await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("#primary svg");
    await page.waitForSelector("#fallback svg");
    assert.deepEqual(pageErrors, []);

    const calls = await page.evaluate(() => window.__kumeyuriCalls);
    assert.ok(calls.length >= 2);
    assert.match(calls[0].source, /^%%\{ animate: 'trace' \}%%\n/);
    assert.equal(calls[0].options.theme, "github");
    assert.equal(calls[0].options.darkTheme, "tokyo-night");
    assert.equal(calls[0].options.speed, 1.5);
    assert.match(calls[1].source, /^%%\{ animate: 'trace' \}%%\ngraph TD\nC --> D/);
    assert.equal(calls[1].options.repeat, true);

    const diagram = page.locator("#primary");
    assert.equal(await diagram.getAttribute("data-autoplay"), "true");
    assert.equal(await diagram.getAttribute("data-controls"), "true");
    assert.equal(await diagram.getAttribute("data-loop"), "false");
    assert.equal(await page.locator("#primary button[data-action='play']").textContent(), "pause");
    assert.equal(await page.locator("#primary input[type='range']").getAttribute("max"), "1");

    await page.locator("#primary button[data-action='play']").click();
    assert.equal(await page.locator("#primary button[data-action='play']").textContent(), "play");

    await page.locator("#primary input[type='range']").evaluate((input) => {
      input.value = "1";
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    assert.equal(await page.locator("#primary #frame-0").getAttribute("opacity"), "0");
    assert.equal(await page.locator("#primary #frame-1").getAttribute("opacity"), "1");

    const exported = await diagram.evaluate((element) => {
      element.seek(1);
      element.play();
      element.pause();
      return element.exportSvg();
    });
    assert.match(exported, /role="img"/);

    const fallback = page.locator("#fallback");
    assert.equal(await fallback.getAttribute("data-autoplay"), "true");
    assert.equal(await fallback.getAttribute("data-loop"), "true");
    assert.equal(await fallback.getAttribute("data-reduced-motion"), "true");
    assert.equal(await page.locator("#fallback button[data-action='play']").textContent(), "play");
    assert.equal(await page.locator("#fallback [data-kumeyuri-csp='true']").getAttribute("style"), null);
    assert.equal(await page.locator("#fallback button[data-action='play']").getAttribute("style"), null);
    assert.equal(await page.locator("#fallback input[type='range']").getAttribute("style"), null);
    const fallbackRect = await fallback.boundingBox();
    const beforeRect = await page.evaluate(() => window.__fallbackBefore);
    assert.ok(fallbackRect.width >= beforeRect.width - 1);
    assert.ok(fallbackRect.height >= beforeRect.height - 1);

    await assertScreenshot(target.name, await diagram.screenshot({ animations: "disabled" }));
  } finally {
    await browser.close();
  }
}

async function assertScreenshot(name, actual) {
  const dir = join(root, "tests/golden/web-component");
  const path = join(dir, `${name}.png`);
  if (updateScreenshots) {
    await mkdir(dir, { recursive: true });
    await writeFile(path, actual);
    return;
  }
  const expected = await readFile(path);
  assertPngMatch(name, actual, expected);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function assertPngMatch(name, actual, expected) {
  const actualImage = decodePng(actual);
  const expectedImage = decodePng(expected);
  assert.equal(actualImage.width, expectedImage.width, `${name} screenshot width mismatch`);
  assert.equal(actualImage.height, expectedImage.height, `${name} screenshot height mismatch`);

  let changedPixels = 0;
  for (let index = 0; index < actualImage.rgba.length; index += 4) {
    const delta = Math.max(
      Math.abs(actualImage.rgba[index] - expectedImage.rgba[index]),
      Math.abs(actualImage.rgba[index + 1] - expectedImage.rgba[index + 1]),
      Math.abs(actualImage.rgba[index + 2] - expectedImage.rgba[index + 2]),
      Math.abs(actualImage.rgba[index + 3] - expectedImage.rgba[index + 3]),
    );
    if (delta > 2) {
      changedPixels += 1;
    }
  }
  const totalPixels = actualImage.width * actualImage.height;
  const budget = Math.max(8, Math.ceil(totalPixels * 0.0005));
  assert.ok(
    changedPixels <= budget,
    `${name} screenshot mismatch: ${changedPixels}/${totalPixels} pixels changed, ` +
      `actual=${sha256(actual)} expected=${sha256(expected)}; ` +
      "rerun with KUMEYURI_UPDATE_WEB_COMPONENT_SCREENSHOTS=1 to update",
  );
}

function decodePng(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(buffer.subarray(0, signature.length).equals(signature), true, "invalid PNG signature");

  let offset = signature.length;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let interlace = 0;
  const idat = [];
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    offset += 12 + length;
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      interlace = data[12];
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }
  }

  assert.equal(bitDepth, 8, "unsupported PNG bit depth");
  assert.equal(interlace, 0, "unsupported interlaced PNG");
  const channels = channelsForColorType(colorType);
  const inflated = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const rgba = Buffer.alloc(width * height * 4);
  let sourceOffset = 0;
  let targetOffset = 0;
  let previous = Buffer.alloc(stride);
  for (let row = 0; row < height; row += 1) {
    const filter = inflated[sourceOffset];
    sourceOffset += 1;
    const raw = Buffer.from(inflated.subarray(sourceOffset, sourceOffset + stride));
    sourceOffset += stride;
    const unfiltered = unfilterRow(filter, raw, previous, channels);
    writeRgbaRow(rgba, targetOffset, unfiltered, colorType);
    previous = unfiltered;
    targetOffset += width * 4;
  }
  return { width, height, rgba };
}

function channelsForColorType(colorType) {
  if (colorType === 0) {
    return 1;
  }
  if (colorType === 2) {
    return 3;
  }
  if (colorType === 4) {
    return 2;
  }
  if (colorType === 6) {
    return 4;
  }
  throw new Error(`unsupported PNG color type ${colorType}`);
}

function unfilterRow(filter, raw, previous, channels) {
  const row = Buffer.alloc(raw.length);
  for (let index = 0; index < raw.length; index += 1) {
    const left = index >= channels ? row[index - channels] : 0;
    const up = previous[index] ?? 0;
    const upLeft = index >= channels ? previous[index - channels] ?? 0 : 0;
    if (filter === 0) {
      row[index] = raw[index];
    } else if (filter === 1) {
      row[index] = (raw[index] + left) & 0xff;
    } else if (filter === 2) {
      row[index] = (raw[index] + up) & 0xff;
    } else if (filter === 3) {
      row[index] = (raw[index] + Math.floor((left + up) / 2)) & 0xff;
    } else if (filter === 4) {
      row[index] = (raw[index] + paeth(left, up, upLeft)) & 0xff;
    } else {
      throw new Error(`unsupported PNG filter ${filter}`);
    }
  }
  return row;
}

function paeth(left, up, upLeft) {
  const estimate = left + up - upLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const upLeftDistance = Math.abs(estimate - upLeft);
  if (leftDistance <= upDistance && leftDistance <= upLeftDistance) {
    return left;
  }
  if (upDistance <= upLeftDistance) {
    return up;
  }
  return upLeft;
}

function writeRgbaRow(rgba, offset, row, colorType) {
  if (colorType === 0) {
    for (let source = 0; source < row.length; source += 1, offset += 4) {
      rgba[offset] = row[source];
      rgba[offset + 1] = row[source];
      rgba[offset + 2] = row[source];
      rgba[offset + 3] = 255;
    }
    return;
  }
  if (colorType === 2) {
    for (let source = 0; source < row.length; source += 3, offset += 4) {
      rgba[offset] = row[source];
      rgba[offset + 1] = row[source + 1];
      rgba[offset + 2] = row[source + 2];
      rgba[offset + 3] = 255;
    }
    return;
  }
  if (colorType === 4) {
    for (let source = 0; source < row.length; source += 2, offset += 4) {
      rgba[offset] = row[source];
      rgba[offset + 1] = row[source];
      rgba[offset + 2] = row[source];
      rgba[offset + 3] = row[source + 1];
    }
    return;
  }
  for (let source = 0; source < row.length; source += 4, offset += 4) {
    rgba[offset] = row[source];
    rgba[offset + 1] = row[source + 1];
    rgba[offset + 2] = row[source + 2];
    rgba[offset + 3] = row[source + 3];
  }
}

async function serve() {
  const server = createServer((request, response) => {
    const path = new URL(request.url ?? "/", "http://127.0.0.1").pathname;
    if (path === "/") {
      response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      response.end(pageHtml());
      return;
    }
    if (path === "/dist/index.js") {
      response.writeHead(200, { "content-type": "text/javascript; charset=utf-8" });
      response.end(componentModule);
      return;
    }
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    response.end("not found");
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.equal(typeof address, "object");
  return { server, url: `http://127.0.0.1:${address.port}/` };
}

function pageHtml() {
  return `<!doctype html>
<html>
  <head>
    <style>
      body { margin: 0; padding: 16px; background: #f6f8fa; }
      kumeyuri-diagram { display: block; width: max-content; color: #24292f; }
      kumeyuri-diagram svg { display: block; width: 360px; height: 180px; background: #ffffff; border: 1px solid #d0d7de; }
      kumeyuri-diagram [data-kumeyuri-controls='true'] { border-radius: 4px; }
      kumeyuri-diagram[csp] { position: relative; }
      kumeyuri-diagram [data-kumeyuri-csp='true'] {
        position: absolute;
        right: 0.5rem;
        bottom: 0.5rem;
        display: flex;
        gap: 0.25rem;
        align-items: center;
        padding: 0.25rem;
        background: rgba(255,255,255,0.9);
        border: 1px solid currentColor;
        font: 12px system-ui,sans-serif;
      }
      kumeyuri-diagram [data-kumeyuri-csp='true'] button {
        box-sizing: border-box;
        min-width: 44px;
        min-height: 44px;
        padding: 0 0.75rem;
      }
      kumeyuri-diagram [data-kumeyuri-csp='true'] input[type='range'] {
        box-sizing: border-box;
        min-width: 8rem;
        min-height: 44px;
      }
    </style>
  </head>
  <body>
    <kumeyuri-diagram
      id="primary"
      inline="graph TD&#10;A --> B"
      animate="trace"
      theme="github"
      dark-theme="tokyo-night"
      speed="1.5"
      autoplay
      controls
    ></kumeyuri-diagram>
    <kumeyuri-diagram
      id="fallback"
      source="graph TD&#10;C --> D"
      animate="trace"
      theme="github"
      autoplay
      controls
      loop
      reduced-motion="reduce"
      csp
    >
      <svg id="ssr-fallback" role="img" width="360" height="180"><title>fallback diagram</title></svg>
      <noscript><img src="/diagrams/fallback.svg" alt="fallback diagram"></noscript>
    </kumeyuri-diagram>
    <script type="module">
      import { defineKumeyuriElement, initKumeyuri } from "/dist/index.js";

      const calls = [];
      window.__kumeyuriCalls = calls;
      const fallbackRect = document.querySelector("#fallback").getBoundingClientRect();
      window.__fallbackBefore = { width: fallbackRect.width, height: fallbackRect.height };
      await initKumeyuri({
        async default() {
          window.__kumeyuriInitialized = true;
        },
        render(source, options) {
          calls.push({ source, options });
          return {
            svg: '<svg role="img"><g id="frame-0" opacity="1"><text>A</text></g><g id="frame-1" opacity="0"><text>B</text></g></svg>',
            frames: [
              { text: "A", durationMs: 10000 },
              { text: "B", durationMs: 10000 }
            ]
          };
        }
      });
      defineKumeyuriElement();
    </script>
  </body>
</html>`;
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}
