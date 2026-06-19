#!/usr/bin/env node
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const defaultManifest = join(repoRoot, "benches/compare/corpus/manifest.json");
const defaultOutDir = join(repoRoot, "benches/compare/results/mermaid-cli");
const defaultBin = join(repoRoot, "node_modules/.bin/mmdc");

function usage() {
  return `Usage:
  node benches/compare/tools/mermaid-cli.mjs [--manifest FILE] [--out-dir DIR] [--allow-failures]
  node benches/compare/tools/mermaid-cli.mjs --input FILE [--input FILE...] [--out-dir DIR]

Options:
  --bin FILE         mmdc binary path. Defaults to MMDC_BIN or local node_modules.
  --chrome-bin FILE  Browser executable. Defaults to MERMAID_CLI_CHROME_BIN, PUPPETEER_EXECUTABLE_PATH, or Playwright Chromium.
  --input FILE       Render one corpus file; repeatable.
  --manifest FILE    Render every input listed in a corpus manifest.
  --out-dir DIR      Directory for .svg and .error.txt outputs.
  --allow-failures   Exit 0 even when upstream cannot render some inputs.
`;
}

function takeValue(args, index, flag) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

function parseArgs(args) {
  const options = {
    bin: process.env.MMDC_BIN || defaultBin,
    chromeBin: process.env.MERMAID_CLI_CHROME_BIN || process.env.PUPPETEER_EXECUTABLE_PATH || "",
    inputs: [],
    manifest: defaultManifest,
    outDir: defaultOutDir,
    allowFailures: false,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--bin":
        options.bin = takeValue(args, index, arg);
        index += 1;
        break;
      case "--chrome-bin":
        options.chromeBin = takeValue(args, index, arg);
        index += 1;
        break;
      case "--input":
        options.inputs.push(takeValue(args, index, arg));
        index += 1;
        break;
      case "--manifest":
        options.manifest = takeValue(args, index, arg);
        index += 1;
        break;
      case "--out-dir":
        options.outDir = takeValue(args, index, arg);
        index += 1;
        break;
      case "--allow-failures":
        options.allowFailures = true;
        break;
      default:
        if (arg.startsWith("--")) {
          throw new Error(`unknown option: ${arg}`);
        }
        options.inputs.push(arg);
        break;
    }
  }

  if (options.inputs.length > 0) {
    options.manifest = undefined;
  }
  return options;
}

async function resolveChromeBin(options) {
  if (options.chromeBin) {
    return options.chromeBin;
  }

  try {
    const { chromium } = await import("playwright");
    return chromium.executablePath();
  } catch {
    return "";
  }
}

async function readManifest(manifestPath) {
  const absoluteManifest = resolve(manifestPath);
  const manifest = JSON.parse(await readFile(absoluteManifest, "utf8"));
  if (!Array.isArray(manifest.inputs)) {
    throw new Error(`manifest has no inputs array: ${absoluteManifest}`);
  }
  return manifest.inputs.map((entry) => {
    if (!entry.id || !entry.path) {
      throw new Error(`manifest entry missing id/path: ${JSON.stringify(entry)}`);
    }
    return {
      id: entry.id,
      file: resolve(dirname(absoluteManifest), entry.path),
    };
  });
}

function inputEntries(paths) {
  return paths.map((path) => {
    const absolute = resolve(path);
    const id = basename(path).replace(/\.[^.]+$/, "");
    return { id, file: absolute };
  });
}

function commandErrorMessage(error) {
  const stderr = typeof error?.stderr === "string" ? error.stderr.trim() : "";
  const stdout = typeof error?.stdout === "string" ? error.stdout.trim() : "";
  const message = error instanceof Error ? error.message : String(error);
  return stderr || stdout || message;
}

async function renderEntry(entry, options) {
  const outputPath = join(options.outDir, `${entry.id}.svg`);
  try {
    const args = [
      "--input",
      entry.file,
      "--output",
      outputPath,
      "--outputFormat",
      "svg",
      "--backgroundColor",
      "transparent",
      "--puppeteerConfigFile",
      options.puppeteerConfig,
      "--quiet",
    ];
    await execFileAsync(options.bin, args, {
      maxBuffer: 1024 * 1024 * 16,
    });
    return {
      id: entry.id,
      status: "ok",
      output: outputPath,
    };
  } catch (error) {
    const message = commandErrorMessage(error);
    const errorPath = join(options.outDir, `${entry.id}.error.txt`);
    await writeFile(errorPath, `${message}\n`);
    return {
      id: entry.id,
      status: "error",
      error: message,
      output: errorPath,
    };
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return 0;
  }

  const entries = options.inputs.length > 0
    ? inputEntries(options.inputs)
    : await readManifest(options.manifest);

  options.outDir = resolve(options.outDir);
  await mkdir(options.outDir, { recursive: true });
  const chromeBin = await resolveChromeBin(options);
  options.puppeteerConfig = join(options.outDir, "puppeteer.generated.json");
  await writeFile(options.puppeteerConfig, `${JSON.stringify({
    executablePath: chromeBin || undefined,
    args: ["--no-sandbox"],
  }, null, 2)}\n`);

  const results = [];
  for (const entry of entries) {
    results.push(await renderEntry(entry, options));
  }

  const failures = results.filter((result) => result.status !== "ok");
  process.stdout.write(`${JSON.stringify({
    tool: "mermaid-cli",
    version: "11.15.0",
    binary: options.bin,
    results,
  }, null, 2)}\n`);
  return failures.length > 0 && !options.allowFailures ? 1 : 0;
}

try {
  const exitCode = await main();
  process.exitCode = exitCode;
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
