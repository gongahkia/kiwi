import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join } from "node:path";
import axe from "axe-core";
import { chromium } from "playwright";

const root = process.cwd();
const componentModule = await readFile(join(root, "packages/kumeyuri/dist/index.js"), "utf8");

const { server, url } = await serve();

try {
  await runAudit(url);
} finally {
  await closeServer(server);
}

async function runAudit(baseUrl) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 768 } });
  try {
    await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("kumeyuri-diagram svg");
    await page.addScriptTag({ content: axe.source });
    const results = await page.evaluate(async () =>
      globalThis.axe.run(document, {
        runOnly: {
          type: "tag",
          values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"],
        },
      }),
    );
    if (results.violations.length > 0) {
      throw new Error(formatViolations(results.violations));
    }
    console.log(`axe ok: ${results.passes.length} checks passed, 0 violations`);
  } finally {
    await browser.close();
  }
}

function formatViolations(violations) {
  return violations
    .map((violation) => {
      const nodes = violation.nodes
        .map((node) => `    ${node.target.join(", ")}: ${node.failureSummary}`)
        .join("\n");
      return `${violation.id} (${violation.impact}): ${violation.help}\n${nodes}`;
    })
    .join("\n\n");
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
  if (typeof address !== "object" || address === null) {
    throw new Error("failed to bind local audit server");
  }
  return { server, url: `http://127.0.0.1:${address.port}/` };
}

function pageHtml() {
  return `<!doctype html>
<html lang="en">
  <head>
    <title>kumeyuri web player accessibility audit</title>
    <style>
      body { margin: 0; padding: 16px; color: #24292f; background: #f6f8fa; font-family: system-ui, sans-serif; }
      kumeyuri-diagram { display: block; width: max-content; color: #24292f; }
      kumeyuri-diagram svg { display: block; width: 360px; height: 180px; background: #ffffff; border: 1px solid #d0d7de; }
      kumeyuri-diagram [data-kumeyuri-controls='true'] { border-radius: 4px; }
    </style>
  </head>
  <body>
    <main>
      <h1>kumeyuri web player</h1>
      <kumeyuri-diagram
        inline="graph TD&#10;A --> B"
        animate="trace"
        theme="github"
        dark-theme="tokyo-night"
        speed="1.5"
        autoplay
        controls
      ></kumeyuri-diagram>
    </main>
    <script type="module">
      import { defineKumeyuriElement, initKumeyuri } from "/dist/index.js";

      await initKumeyuri({
        async default() {},
        render() {
          return {
            svg: '<svg role="img" aria-labelledby="kumeyuri-title kumeyuri-desc"><title id="kumeyuri-title">Checkout flow</title><desc id="kumeyuri-desc">Two-frame checkout flow animation.</desc><g id="frame-0" opacity="1"><text>A</text></g><g id="frame-1" opacity="0"><text>B</text></g></svg>',
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
