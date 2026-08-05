import assert from "node:assert/strict";
import { createServer } from "node:http";
import { after, describe, it } from "node:test";

import { smokeConfig, smokeDeployment } from "./smoke-deployment.mjs";

const servers = [];

async function startServer(handler) {
  const server = createServer(handler);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  servers.push(server);
  return `http://127.0.0.1:${server.address().port}`;
}

function writeJson(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

after(async () => {
  await Promise.all(
    servers.map((server) => new Promise((resolve) => server.close(() => resolve())))
  );
});

describe("smoke deployment", () => {
  it("checks readyz and API search", async () => {
    const baseUrl = await startServer((request, response) => {
      const url = new URL(request.url ?? "/", "http://127.0.0.1");
      if (url.pathname === "/readyz") {
        writeJson(response, 200, { status: "ok" });
        return;
      }
      if (url.pathname === "/api/v1/search" && url.searchParams.get("q") === "API") {
        writeJson(response, 200, { matches: [{ entry: { term: "API" }, score: 1 }] });
        return;
      }
      writeJson(response, 404, { error: "not_found" });
    });

    const result = await smokeDeployment({ baseUrl, query: "API", timeoutMs: 1000 });

    assert.equal(result.matchCount, 1);
    assert.equal(result.url, baseUrl);
  });

  it("fails when search returns no matches", async () => {
    const baseUrl = await startServer((request, response) => {
      const url = new URL(request.url ?? "/", "http://127.0.0.1");
      writeJson(response, 200, url.pathname === "/readyz" ? { status: "ok" } : { matches: [] });
    });

    await assert.rejects(
      () => smokeDeployment({ baseUrl, query: "MISS", timeoutMs: 1000 }),
      /search returned no matches/
    );
  });

  it("resolves URL input from env or Terraform output", () => {
    assert.equal(
      smokeConfig([], { WAT_DEPLOY_URL: "https://wat.example.com/" }).baseUrl,
      "https://wat.example.com"
    );
    assert.equal(
      smokeConfig(["--terraform-dir", "infra/fly"], {}, () => "https://fly.example.com\n").baseUrl,
      "https://fly.example.com"
    );
    assert.equal(
      smokeConfig(["--", "--url", "https://pnpm.example.com"], {}).baseUrl,
      "https://pnpm.example.com"
    );
  });
});
