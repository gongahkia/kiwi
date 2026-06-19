#!/usr/bin/env node
import { copyFile, mkdir, readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const defaultInput = "metrics/dashboard.svg";
const defaultArchiveRoot = "metrics/archive";

function usage() {
  return `Usage:
  node scripts/archive-metrics-dashboard.mjs [--input FILE] [--archive-root DIR] [--date YYYY-MM-DD]
`;
}

function takeValue(args, index, flag) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function parseArgs(args) {
  const options = {
    input: defaultInput,
    archiveRoot: defaultArchiveRoot,
    date: today(),
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--input":
        options.input = takeValue(args, index, arg);
        index += 1;
        break;
      case "--archive-root":
        options.archiveRoot = takeValue(args, index, arg);
        index += 1;
        break;
      case "--date":
        options.date = takeValue(args, index, arg);
        index += 1;
        break;
      default:
        throw new Error(`unknown option: ${arg}`);
    }
  }

  if (!/^\d{4}-\d{2}-\d{2}$/.test(options.date)) {
    throw new Error("--date must be YYYY-MM-DD");
  }
  return options;
}

async function assertSvg(path) {
  const text = await readFile(path, "utf8");
  if (!text.includes("<svg") || !text.includes("</svg>")) {
    throw new Error(`${path} is not an SVG document`);
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  const input = resolve(options.input);
  await assertSvg(input);
  const year = options.date.slice(0, 4);
  const output = resolve(options.archiveRoot, year, "dashboard.svg");
  await mkdir(dirname(output), { recursive: true });
  await copyFile(input, output);
  process.stdout.write(`${output}\n`);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
