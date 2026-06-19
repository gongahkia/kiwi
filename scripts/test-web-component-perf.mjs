import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join } from "node:path";
import { chromium } from "playwright";

const root = process.cwd();
const runs = positiveInteger(process.env.KUMEYURI_WEB_PLAYER_PERF_RUNS ?? "7");
const fcrBudgetMs = positiveNumber(process.env.KUMEYURI_WEB_PLAYER_FCR_BUDGET_MS ?? "1000");
const componentModule = await readFile(join(root, "packages/kumeyuri/dist/index.js"), "utf8");

const { server, url } = await serve();

try {
  await runPerf(url);
} finally {
  await closeServer(server);
}

async function runPerf(baseUrl) {
  const browser = await chromium.launch();
  const samples = [];
  try {
    for (let i = 0; i < runs; i += 1) {
      const page = await browser.newPage({ viewport: { width: 1024, height: 768 } });
      try {
        await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
        await page.waitForSelector("kumeyuri-diagram svg");
        await page.waitForFunction(() => performance.getEntriesByName("kumeyuri-contentful-render").length > 0);
        samples.push(
          await page.evaluate(() => {
            const fcr = performance.getEntriesByName("kumeyuri-contentful-render")[0];
            const browserFcp = performance.getEntriesByName("first-contentful-paint")[0];
            return {
              fcrMs: fcr.startTime,
              fcpMs: browserFcp?.startTime ?? null,
            };
          }),
        );
      } finally {
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }

  const fcrSamples = samples.map((sample) => sample.fcrMs);
  const median = percentile(fcrSamples, 0.5);
  const p95 = percentile(fcrSamples, 0.95);
  assert.ok(
    p95 <= fcrBudgetMs,
    `web player FCR p95 ${formatMs(p95)} exceeds budget ${formatMs(fcrBudgetMs)}; samples=${fcrSamples.map(formatMs).join(",")}`,
  );
  console.log(
    `web-player fcr ok: median=${formatMs(median)} p95=${formatMs(p95)} budget=${formatMs(fcrBudgetMs)} runs=${runs}`,
  );
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
    <title>kumeyuri web player perf</title>
    <style>
      body { margin: 0; padding: 16px; color: #24292f; background: #ffffff; font-family: system-ui, sans-serif; }
      kumeyuri-diagram { display: block; width: max-content; color: #24292f; }
      kumeyuri-diagram svg { display: block; width: 360px; height: 180px; background: #ffffff; border: 1px solid #d0d7de; }
      kumeyuri-diagram [data-kumeyuri-controls='true'] { border-radius: 4px; }
    </style>
    <script>
      const markContentfulRender = () => {
        if (document.querySelector("kumeyuri-diagram svg") && performance.getEntriesByName("kumeyuri-contentful-render").length === 0) {
          performance.mark("kumeyuri-contentful-render");
          observer.disconnect();
        }
      };
      const observer = new MutationObserver(markContentfulRender);
      observer.observe(document.documentElement, { childList: true, subtree: true });
    </script>
  </head>
  <body>
    <kumeyuri-diagram
      inline="graph TD&#10;A[Cart] --> B{Signed in?}&#10;B -->|Yes| C[Checkout]&#10;B -->|No| D[Login]&#10;D --> C"
      animate="trace"
      theme="github"
      dark-theme="tokyo-night"
      speed="1.25"
      autoplay
      controls
    ></kumeyuri-diagram>
    <script type="module">
      import { defineKumeyuriElement, initKumeyuri } from "/dist/index.js";

      await initKumeyuri({
        async default() {},
        render() {
          return {
            svg: '<svg role="img" aria-labelledby="kumeyuri-title kumeyuri-desc"><title id="kumeyuri-title">Checkout flow</title><desc id="kumeyuri-desc">A checkout flow animation.</desc><g id="frame-0" opacity="1"><text>Cart</text></g><g id="frame-1" opacity="0"><text>Checkout</text></g></svg>',
            frames: [
              { text: "Cart", durationMs: 10000 },
              { text: "Checkout", durationMs: 10000 }
            ]
          };
        }
      });
      defineKumeyuriElement();
    </script>
  </body>
</html>`;
}

function positiveInteger(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`expected positive integer, got ${JSON.stringify(value)}`);
  }
  return parsed;
}

function positiveNumber(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`expected positive number, got ${JSON.stringify(value)}`);
  }
  return parsed;
}

function percentile(values, fraction) {
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1);
  return sorted[index];
}

function formatMs(value) {
  return `${value.toFixed(1)}ms`;
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}
