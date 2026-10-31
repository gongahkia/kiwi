import http from "node:http";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../dist/", import.meta.url));
const port = Number(process.env.PORT || 4173);
const prefix = (process.env.BASE_PATH || "/").replace(/\/*$/, "/");
const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".wasm": "application/wasm",
  ".svg": "image/svg+xml",
  ".otf": "font/otf",
  ".woff2": "font/woff2",
  ".txt": "text/plain; charset=utf-8",
};

export function createServer() {
  return http.createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(
        new URL(request.url, "http://localhost").pathname,
      );
      if (!pathname.startsWith(prefix)) {
        response.writeHead(404).end("Not found");
        return;
      }
      const relative = pathname.slice(prefix.length) || "index.html";
      const filename = path.resolve(root, relative);
      if (!filename.startsWith(root)) {
        response.writeHead(403).end("Forbidden");
        return;
      }
      const info = await stat(filename);
      if (!info.isFile()) {
        response.writeHead(404).end("Not found");
        return;
      }
      const content = await readFile(filename);
      response.writeHead(200, {
        "Content-Type":
          mime[path.extname(filename)] || "application/octet-stream",
        "Cache-Control": "no-store",
      });
      response.end(request.method === "HEAD" ? undefined : content);
    } catch {
      response
        .writeHead(404)
        .end("Not found. Build the photobooth first with npm run build.");
    }
  });
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const server = createServer();
  server.listen(port, "127.0.0.1", () =>
    console.log(`strok photobooth: http://localhost:${port}${prefix}`),
  );
}
