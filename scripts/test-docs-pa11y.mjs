import { createReadStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, relative, resolve, sep } from "node:path";
import pa11y from "pa11y";
import { chromium } from "playwright";

const root = process.cwd();
const docsRoot = resolve(root, "target/mdbook");
const pages = await htmlPages(docsRoot);

if (pages.length === 0) {
  throw new Error(`no generated mdBook HTML pages found in ${docsRoot}`);
}

const { server, url } = await serve(docsRoot);
const failures = [];

try {
  for (const page of pages) {
    const pageUrl = new URL(routeFor(page), url).href;
    const result = await pa11y(pageUrl, {
      standard: "WCAG2AA",
      includeNotices: false,
      includeWarnings: false,
      timeout: 30000,
      chromeLaunchConfig: {
        executablePath: chromium.executablePath(),
        args: ["--no-sandbox", "--disable-dev-shm-usage"],
      },
    });
    if (result.issues.length > 0) {
      failures.push({ page: routeFor(page), issues: result.issues });
      console.error(`not ok ${routeFor(page)}: ${result.issues.length} issue(s)`);
      continue;
    }
    console.log(`ok ${routeFor(page)}`);
  }
} finally {
  await closeServer(server);
}

if (failures.length > 0) {
  throw new Error(formatFailures(failures));
}

async function htmlPages(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const pages = [];
  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      pages.push(...(await htmlPages(path)));
      continue;
    }
    if (
      entry.isFile() &&
      entry.name.endsWith(".html") &&
      relative(docsRoot, path) !== "toc.html"
    ) {
      pages.push(path);
    }
  }
  return pages.sort();
}

function routeFor(page) {
  return `/${relative(docsRoot, page)
    .split(sep)
    .map((part) => encodeURIComponent(part))
    .join("/")}`;
}

async function serve(rootDir) {
  const server = createServer(async (request, response) => {
    try {
      const requestPath = decodeURIComponent(new URL(request.url ?? "/", "http://127.0.0.1").pathname);
      let filePath = resolve(rootDir, `.${requestPath}`);
      if (!filePath.startsWith(`${rootDir}${sep}`) && filePath !== rootDir) {
        response.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        response.end("forbidden");
        return;
      }
      let fileStat = await stat(filePath).catch(() => null);
      if (fileStat?.isDirectory()) {
        filePath = join(filePath, "index.html");
        fileStat = await stat(filePath).catch(() => null);
      }
      if (!fileStat?.isFile()) {
        response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
        response.end("not found");
        return;
      }
      response.writeHead(200, { "content-type": contentType(filePath) });
      createReadStream(filePath).pipe(response);
    } catch (error) {
      response.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
      response.end(error instanceof Error ? error.message : String(error));
    }
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  const address = server.address();
  if (typeof address !== "object" || address === null) {
    throw new Error("failed to bind local docs server");
  }
  return { server, url: `http://127.0.0.1:${address.port}/` };
}

function contentType(path) {
  switch (extname(path)) {
    case ".css":
      return "text/css; charset=utf-8";
    case ".js":
      return "text/javascript; charset=utf-8";
    case ".svg":
      return "image/svg+xml";
    case ".png":
      return "image/png";
    case ".wasm":
      return "application/wasm";
    case ".woff2":
      return "font/woff2";
    default:
      return "text/html; charset=utf-8";
  }
}

function formatFailures(failures) {
  return failures
    .map(({ page, issues }) => {
      const details = issues
        .map((issue) => `    ${issue.code}: ${issue.message}\n    selector: ${issue.selector}`)
        .join("\n");
      return `${page}\n${details}`;
    })
    .join("\n\n");
}

function closeServer(server) {
  return new Promise((resolveClose, reject) => {
    server.close((error) => (error ? reject(error) : resolveClose()));
  });
}
