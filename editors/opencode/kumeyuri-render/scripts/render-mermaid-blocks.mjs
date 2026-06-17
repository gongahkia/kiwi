#!/usr/bin/env node
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const MERMAID_FENCE = /^([ \t]*)```([^\n`]*)\n([\s\S]*?)\n\1```[ \t]*$/gm;

export function parseArgs(argv) {
  const options = {
    input: undefined,
    format: "text",
    kumeyuri: process.env.KUMEYURI_BIN || "kumeyuri",
    replace: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--format") {
      options.format = requireValue(argv, (index += 1), "--format");
    } else if (arg === "--kumeyuri") {
      options.kumeyuri = requireValue(argv, (index += 1), "--kumeyuri");
    } else if (arg === "--replace") {
      options.replace = true;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (!options.input) {
      options.input = arg;
    } else {
      throw new Error(`unexpected argument: ${arg}`);
    }
  }

  if (!["text", "svg"].includes(options.format)) {
    throw new Error(`unsupported format: ${options.format}`);
  }
  return options;
}

export function findMermaidBlocks(markdown) {
  const blocks = [];
  for (const match of markdown.matchAll(MERMAID_FENCE)) {
    const info = match[2].trim().toLowerCase();
    if (!info.split(/\s+/).some((part) => part === "mermaid" || part === "mmd")) {
      continue;
    }
    blocks.push({
      index: blocks.length + 1,
      start: match.index,
      end: match.index + match[0].length,
      fence: match[0],
      source: match[3],
    });
  }
  return blocks;
}

export function injectRenderedBlocks(markdown, blocks, rendered, options = {}) {
  let cursor = 0;
  let output = "";
  for (const block of blocks) {
    output += markdown.slice(cursor, block.start);
    const renderedBlock = fencedOutput(rendered.get(block.index), options.format || "text");
    output += options.replace ? renderedBlock : `${block.fence}\n\n${renderedBlock}`;
    cursor = block.end;
  }
  output += markdown.slice(cursor);
  return output;
}

export async function renderMarkdown(markdown, options) {
  const blocks = findMermaidBlocks(markdown);
  if (blocks.length === 0) {
    return markdown;
  }

  const rendered = new Map();
  const dir = await mkdtemp(path.join(tmpdir(), "kumeyuri-opencode-"));
  try {
    for (const block of blocks) {
      const input = path.join(dir, `block-${block.index}.mmd`);
      await writeFile(input, block.source, "utf8");
      let stdout;
      try {
        ({ stdout } = await execFileAsync(options.kumeyuri, ["render", input, "--format", options.format], {
          maxBuffer: 10 * 1024 * 1024,
        }));
      } catch (error) {
        const detail = error?.stderr || error?.message || String(error);
        throw new Error(`failed to render Mermaid block ${block.index}: ${detail.trim()}`);
      }
      rendered.set(block.index, stdout.trimEnd());
    }
  } finally {
    await rm(dir, { recursive: true, force: true });
  }

  return injectRenderedBlocks(markdown, blocks, rendered, options);
}

function fencedOutput(value, format) {
  const fence = format === "svg" ? "svg" : "text";
  return `\`\`\`${fence}\n${value || ""}\n\`\`\``;
}

function requireValue(argv, index, flag) {
  if (!argv[index]) {
    throw new Error(`${flag} requires a value`);
  }
  return argv[index];
}

async function readInput(input) {
  if (input) {
    return readFile(input, "utf8");
  }
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}

function usage() {
  return `Usage: render-mermaid-blocks.mjs [--format text|svg] [--replace] [--kumeyuri PATH] [markdown-file]

Reads Markdown from a file or stdin and appends kumeyuri renders below Mermaid fences.`;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  const markdown = await readInput(options.input);
  process.stdout.write(await renderMarkdown(markdown, options));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
