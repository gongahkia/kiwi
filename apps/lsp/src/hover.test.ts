import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { afterEach, describe, expect, it } from "vitest";

import { hoverAtPosition, tokenAtPosition } from "./hover.js";

const root = new URL("../../..", import.meta.url);
const servers: ChildProcessWithoutNullStreams[] = [];

interface RpcResponse {
  id?: number;
  result?: unknown;
}

function writeMessage(server: ChildProcessWithoutNullStreams, message: unknown) {
  const body = JSON.stringify(message);
  server.stdin.write(`Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`);
}

function waitForResponse(server: ChildProcessWithoutNullStreams, id: number): Promise<RpcResponse> {
  let buffer = "";

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timeout waiting for ${id}`)), 5000);
    const onData = (chunk: Buffer) => {
      buffer += chunk.toString("utf8");

      while (true) {
        const headerEnd = buffer.indexOf("\r\n\r\n");
        if (headerEnd === -1) {
          return;
        }

        const header = buffer.slice(0, headerEnd);
        const length = Number(header.match(/Content-Length: (\d+)/i)?.[1]);
        if (!Number.isFinite(length)) {
          reject(new Error("missing content length"));
          return;
        }

        const bodyStart = headerEnd + 4;
        const bodyEnd = bodyStart + length;
        if (buffer.length < bodyEnd) {
          return;
        }

        const rawBody = buffer.slice(bodyStart, bodyEnd);
        buffer = buffer.slice(bodyEnd);
        const parsed = JSON.parse(rawBody) as RpcResponse;
        if (parsed.id === id) {
          clearTimeout(timer);
          server.stdout.off("data", onData);
          resolve(parsed);
          return;
        }
      }
    };

    server.stdout.on("data", onData);
  });
}

async function startServer(): Promise<ChildProcessWithoutNullStreams> {
  const server = spawn(process.execPath, ["apps/lsp/dist/index.js"], {
    cwd: root.pathname,
    env: { ...process.env }
  });
  servers.push(server);

  const initialized = waitForResponse(server, 1);
  writeMessage(server, {
    id: 1,
    jsonrpc: "2.0",
    method: "initialize",
    params: {
      capabilities: {},
      processId: process.pid,
      rootUri: null
    }
  });
  await initialized;
  writeMessage(server, {
    jsonrpc: "2.0",
    method: "initialized",
    params: {}
  });

  return server;
}

afterEach(() => {
  for (const server of servers.splice(0)) {
    server.kill();
  }
});

describe("wat lsp hover", () => {
  it("extracts a token at a position", () => {
    expect(tokenAtPosition("const protocol = TLS;", { character: 18, line: 0 })).toBe("TLS");
  });

  it("builds hover markdown for a seed token", async () => {
    const hover = await hoverAtPosition("Use TLS for transport.", { character: 5, line: 0 });

    expect(hover?.contents).toMatchObject({
      kind: "markdown",
      value: expect.stringContaining("Transport Layer Security")
    });
  });

  it("returns hover content over stdio LSP", async () => {
    const server = await startServer();

    writeMessage(server, {
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          languageId: "plaintext",
          text: "Use TLS for transport.",
          uri: "file:///wat-test.txt",
          version: 1
        }
      }
    });
    const hoverResponse = waitForResponse(server, 2);
    writeMessage(server, {
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/hover",
      params: {
        position: { character: 5, line: 0 },
        textDocument: { uri: "file:///wat-test.txt" }
      }
    });

    const response = await hoverResponse;

    expect(response.result).toMatchObject({
      contents: {
        kind: "markdown",
        value: expect.stringContaining("Transport Layer Security")
      }
    });
  });
});
