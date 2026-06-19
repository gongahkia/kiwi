#!/usr/bin/env node
import { spawn } from "node:child_process";

const expectedTools = [
  "lint_diagram",
  "list_diagram_types",
  "list_themes",
  "play_diagram",
  "render_diagram",
];

function startServer() {
  return spawn("cargo", ["run", "-q", "-p", "kumeyuri-cli", "--", "mcp", "--transport", "stdio"], {
    stdio: ["pipe", "pipe", "pipe"],
  });
}

function client(child) {
  let nextId = 1;
  let buffer = "";
  const pending = new Map();
  const stderr = [];

  child.stdout.on("data", (chunk) => {
    buffer += chunk;
    for (;;) {
      const index = buffer.indexOf("\n");
      if (index < 0) break;
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (!line) continue;
      const message = JSON.parse(line);
      const waiter = pending.get(message.id);
      if (waiter) {
        pending.delete(message.id);
        waiter.resolve(message);
      }
    }
  });
  child.stderr.on("data", (chunk) => stderr.push(chunk.toString()));

  function request(method, params = {}) {
    const id = nextId++;
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`timeout waiting for ${method}; stderr=${stderr.join("")}`));
      }, 30000);
      pending.set(id, {
        resolve: (message) => {
          clearTimeout(timer);
          resolve(message);
        },
      });
    });
  }

  function notify(method, params = {}) {
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
  }

  return { request, notify };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function toolText(response) {
  const text = response.result?.content?.[0]?.text;
  assert(typeof text === "string", `expected text content: ${JSON.stringify(response)}`);
  return JSON.parse(text);
}

async function main() {
  const child = startServer();
  const mcp = client(child);
  try {
    const init = await mcp.request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "kumeyuri-mcp-smoke", version: "0.0.0" },
    });
    assert(init.result?.capabilities?.tools, "server did not advertise tools capability");
    mcp.notify("notifications/initialized");

    const listed = await mcp.request("tools/list");
    const toolNames = listed.result?.tools?.map((tool) => tool.name).sort();
    assert(JSON.stringify(toolNames) === JSON.stringify(expectedTools), `unexpected tools: ${toolNames}`);

    const rendered = toolText(await mcp.request("tools/call", {
      name: "render_diagram",
      arguments: { source: "graph TD\nA --> B\n", format: "text" },
    }));
    assert(rendered.encoding === "utf8", "render_diagram should return utf8 text");
    assert(rendered.content.includes("A") && rendered.content.includes("B"), "render output missing nodes");

    const linted = toolText(await mcp.request("tools/call", {
      name: "lint_diagram",
      arguments: { source: "graph TD\nA\n" },
    }));
    assert(linted.ok === false, "lint_diagram should flag orphan node");
    assert(linted.warnings[0]?.code === "flowchart.orphan_node", "lint warning code mismatch");

    const themes = toolText(await mcp.request("tools/call", {
      name: "list_themes",
      arguments: {},
    }));
    assert(themes.themes.some((theme) => theme.name === "default"), "default theme missing");

    const diagramTypes = toolText(await mcp.request("tools/call", {
      name: "list_diagram_types",
      arguments: {},
    }));
    assert(diagramTypes.diagram_types.some((diagram) => diagram.id === "flowchart"), "flowchart type missing");

    const play = await mcp.request("tools/call", {
      name: "play_diagram",
      arguments: { file: "diagram.kumecast", speed: 0 },
    });
    assert(play.error?.message?.includes("positive finite"), "play_diagram validation error missing");
  } finally {
    child.stdin.end();
    setTimeout(() => child.kill("SIGTERM"), 250);
  }
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
