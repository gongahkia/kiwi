#!/usr/bin/env node
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const defaultManifest = join(repoRoot, "benches/compare/corpus/manifest.json");
const defaultOutDir = join(repoRoot, "benches/compare/results/pgavlin-mermaid-ascii");

function usage() {
  return `Usage:
  node benches/compare/tools/pgavlin-mermaid-ascii.mjs [--manifest FILE] [--out-dir DIR] [--allow-failures]
  node benches/compare/tools/pgavlin-mermaid-ascii.mjs --input FILE [--input FILE...] [--out-dir DIR]
  node benches/compare/tools/pgavlin-mermaid-ascii.mjs --input FILE --stdout

Options:
  --bin FILE         mermaid-ascii binary path. Defaults to PGAVLIN_MERMAID_ASCII_BIN, MERMAID_ASCII_BIN, or PATH lookup.
  --input FILE       Render one corpus file; repeatable.
  --manifest FILE    Render every input listed in a corpus manifest.
  --out-dir DIR      Directory for .txt and .error.txt outputs.
  --stdout           Print a single input render to stdout.
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
    bin: process.env.PGAVLIN_MERMAID_ASCII_BIN || process.env.MERMAID_ASCII_BIN || "mermaid-ascii",
    inputs: [],
    manifest: defaultManifest,
    outDir: defaultOutDir,
    stdout: false,
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
      case "--stdout":
        options.stdout = true;
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
  if (options.stdout && options.inputs.length !== 1) {
    throw new Error("--stdout requires exactly one input");
  }
  return options;
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
  try {
    const { stdout } = await execFileAsync(options.bin, [
      "--file",
      entry.file,
      "--ascii",
    ], {
      maxBuffer: 1024 * 1024 * 16,
    });
    const normalized = stdout.endsWith("\n") ? stdout : `${stdout}\n`;

    if (options.stdout) {
      process.stdout.write(normalized);
      return { id: entry.id, status: "ok" };
    }

    const outputPath = join(options.outDir, `${entry.id}.txt`);
    await writeFile(outputPath, normalized);
    return {
      id: entry.id,
      status: "ok",
      output: outputPath,
    };
  } catch (error) {
    const message = commandErrorMessage(error);
    if (options.stdout) {
      process.stderr.write(`${entry.id}: ${message}\n`);
      return { id: entry.id, status: "error", error: message };
    }

    const outputPath = join(options.outDir, `${entry.id}.error.txt`);
    await writeFile(outputPath, `${message}\n`);
    return {
      id: entry.id,
      status: "error",
      error: message,
      output: outputPath,
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

  if (!options.stdout) {
    options.outDir = resolve(options.outDir);
    await mkdir(options.outDir, { recursive: true });
  }

  const results = [];
  for (const entry of entries) {
    results.push(await renderEntry(entry, options));
  }

  const failures = results.filter((result) => result.status !== "ok");
  if (!options.stdout) {
    process.stdout.write(`${JSON.stringify({
      tool: "pgavlin/mermaid-ascii",
      binary: options.bin,
      results,
    }, null, 2)}\n`);
  }
  return failures.length > 0 && !options.allowFailures ? 1 : 0;
}

try {
  const exitCode = await main();
  process.exitCode = exitCode;
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
