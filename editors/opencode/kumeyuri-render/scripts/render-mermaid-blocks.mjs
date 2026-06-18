#!/usr/bin/env node
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

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
  const lines = markdown.split("\n");
  const starts = lineStarts(lines);
  for (let index = 0; index < lines.length; index += 1) {
    const opening = parseMermaidOpening(lines[index]);
    if (!opening) {
      continue;
    }
    const closingIndex = findClosingFence(lines, index + 1, opening.indent);
    if (closingIndex === -1) {
      continue;
    }
    const start = starts[index];
    const sourceStart = Math.min(starts[index] + lines[index].length + 1, markdown.length);
    const closeStart = starts[closingIndex];
    const sourceEnd = closeStart > sourceStart && markdown[closeStart - 1] === "\n" ? closeStart - 1 : closeStart;
    const end = starts[closingIndex] + lines[closingIndex].length;
    blocks.push({
      index: blocks.length + 1,
      start,
      end,
      fence: markdown.slice(start, end),
      source: markdown.slice(sourceStart, sourceEnd),
    });
    index = closingIndex;
  }
  return blocks;
}

function lineStarts(lines) {
  const starts = [];
  let offset = 0;
  for (const line of lines) {
    starts.push(offset);
    offset += line.length + 1;
  }
  return starts;
}

function parseMermaidOpening(line) {
  const indentEnd = readIndentEnd(line);
  if (!line.startsWith("```", indentEnd)) {
    return undefined;
  }
  const info = line.slice(indentEnd + 3);
  if (info.includes("`") || !hasMermaidInfo(info)) {
    return undefined;
  }
  return { indent: line.slice(0, indentEnd) };
}

function readIndentEnd(line) {
  let index = 0;
  while (line[index] === " " || line[index] === "\t") {
    index += 1;
  }
  return index;
}

function hasMermaidInfo(info) {
  return splitWhitespace(info.toLowerCase()).some((part) => part === "mermaid" || part === "mmd");
}

function splitWhitespace(value) {
  const parts = [];
  let part = "";
  for (const char of value) {
    if (char.trim() === "") {
      if (part) {
        parts.push(part);
        part = "";
      }
    } else {
      part += char;
    }
  }
  if (part) {
    parts.push(part);
  }
  return parts;
}

function findClosingFence(lines, start, indent) {
  for (let index = start; index < lines.length; index += 1) {
    if (isClosingFence(lines[index], indent)) {
      return index;
    }
  }
  return -1;
}

function isClosingFence(line, indent) {
  const fence = `${indent}\`\`\``;
  if (!line.startsWith(fence)) {
    return false;
  }
  const rest = line.slice(fence.length);
  return Array.from(rest).every((char) => char === " " || char === "\t");
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
