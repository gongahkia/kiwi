import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join } from "node:path";
import { chromium } from "playwright";

const root = process.cwd();
const componentModule = await readFile(join(root, "packages/kumeyuri/dist/index.js"), "utf8");

const { server, url } = await serve();

try {
  await runKeyboardSmoke(url);
} finally {
  await closeServer(server);
}

async function runKeyboardSmoke(baseUrl) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 768 } });
  try {
    await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("kumeyuri-diagram [data-kumeyuri-controls='true']");
    assert.deepEqual(await controlOrder(page), ["play", "range:Animation frame", "restart"]);

    await page.keyboard.press("Tab");
    assert.equal(await focusedControl(page), "play");
    await page.keyboard.press("Enter");
    assert.equal(await page.locator("button[data-action='play']").textContent(), "pause");
    assert.equal(await page.locator("button[data-action='play']").getAttribute("aria-label"), "Pause animation");

    await page.keyboard.press("Tab");
    assert.equal(await focusedControl(page), "range:Animation frame");
    await page.keyboard.press("ArrowRight");
    assert.equal(await page.locator("input[type='range']").inputValue(), "1");
    assert.equal(await page.locator("#frame-0").getAttribute("opacity"), "0");
    assert.equal(await page.locator("#frame-1").getAttribute("opacity"), "1");
    assert.equal(await page.locator("button[data-action='play']").textContent(), "play");

    await page.keyboard.press("Tab");
    assert.equal(await focusedControl(page), "restart");
    await page.keyboard.press("Enter");
    assert.equal(await page.locator("input[type='range']").inputValue(), "0");
    assert.equal(await page.locator("#frame-0").getAttribute("opacity"), "1");
    assert.equal(await page.locator("#frame-1").getAttribute("opacity"), "0");
    assert.equal(await page.locator("button[data-action='play']").textContent(), "play");
  } finally {
    await browser.close();
  }
  console.log("keyboard ok: play, range, restart");
}

async function controlOrder(page) {
  return page.evaluate(() => {
    const controlName = (element) => {
      if (element instanceof HTMLButtonElement && element.dataset.action) {
        return element.dataset.action;
      }
      if (element instanceof HTMLInputElement) {
        return `${element.type}:${element.getAttribute("aria-label") ?? ""}`;
      }
      return element?.tagName.toLowerCase() ?? "";
    };
    return Array.from(
      document.querySelectorAll("[data-kumeyuri-controls='true'] button, [data-kumeyuri-controls='true'] input"),
    ).map((element) => controlName(element));
  });
}

async function focusedControl(page) {
  return page.evaluate(() => {
    const element = document.activeElement;
    if (element instanceof HTMLButtonElement && element.dataset.action) {
      return element.dataset.action;
    }
    if (element instanceof HTMLInputElement) {
      return `${element.type}:${element.getAttribute("aria-label") ?? ""}`;
    }
    return element?.tagName.toLowerCase() ?? "";
  });
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
<html lang="en">
  <head>
    <title>kumeyuri keyboard smoke</title>
    <style>
      body { margin: 0; padding: 16px; color: #24292f; background: #f6f8fa; font-family: system-ui, sans-serif; }
      kumeyuri-diagram { display: block; width: max-content; color: #24292f; }
      kumeyuri-diagram svg { display: block; width: 360px; height: 180px; background: #ffffff; border: 1px solid #d0d7de; }
    </style>
  </head>
  <body>
    <kumeyuri-diagram inline="graph TD&#10;A --> B" animate="trace" controls></kumeyuri-diagram>
    <script type="module">
      import { defineKumeyuriElement, initKumeyuri } from "/dist/index.js";

      await initKumeyuri({
        async default() {},
        render() {
          return {
            svg: '<svg role="img" aria-labelledby="kumeyuri-title kumeyuri-desc"><title id="kumeyuri-title">Keyboard flow</title><desc id="kumeyuri-desc">Two-frame keyboard test.</desc><g id="frame-0" opacity="1"><text>A</text></g><g id="frame-1" opacity="0"><text>B</text></g></svg>',
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
