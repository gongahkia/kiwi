import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join } from "node:path";
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
    await page.waitForSelector("kumeyuri-diagram svg");
    assert.deepEqual(pageErrors, []);

    const calls = await page.evaluate(() => window.__kumeyuriCalls);
    assert.equal(calls.length, 1);
    assert.match(calls[0].source, /^%%\{ animate: 'trace' \}%%\n/);
    assert.equal(calls[0].options.theme, "github");
    assert.equal(calls[0].options.darkTheme, "tokyo-night");
    assert.equal(calls[0].options.speed, 1.5);

    const diagram = page.locator("kumeyuri-diagram");
    assert.equal(await diagram.getAttribute("data-autoplay"), "true");
    assert.equal(await diagram.getAttribute("data-controls"), "true");
    assert.equal(await page.locator("button[data-action='play']").textContent(), "pause");
    assert.equal(await page.locator("input[type='range']").getAttribute("max"), "1");

    await page.locator("button[data-action='play']").click();
    assert.equal(await page.locator("button[data-action='play']").textContent(), "play");

    await page.locator("input[type='range']").evaluate((input) => {
      input.value = "1";
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    assert.equal(await page.locator("#frame-0").getAttribute("opacity"), "0");
    assert.equal(await page.locator("#frame-1").getAttribute("opacity"), "1");

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
  assert.equal(
    sha256(actual),
    sha256(expected),
    `${name} screenshot mismatch; rerun with KUMEYURI_UPDATE_WEB_COMPONENT_SCREENSHOTS=1 to update`,
  );
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
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
    </style>
  </head>
  <body>
    <kumeyuri-diagram
      inline="graph TD&#10;A --> B"
      animate="trace"
      theme="github"
      dark-theme="tokyo-night"
      speed="1.5"
      autoplay
      controls
    ></kumeyuri-diagram>
    <script type="module">
      import { defineKumeyuriElement, initKumeyuri } from "/dist/index.js";

      const calls = [];
      window.__kumeyuriCalls = calls;
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
