#!/usr/bin/env node
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const defaultManifest = join(repoRoot, "benches/compare/corpus/manifest.json");
const defaultOutDir = join(repoRoot, "benches/compare/results/kumeyuri");
const defaultBin = join(repoRoot, "target/release/kumeyuri");

function usage() {
  return `Usage:
  node benches/compare/tools/kumeyuri.mjs [--manifest FILE] [--out-dir DIR] [--format text|svg] [--allow-failures]
  node benches/compare/tools/kumeyuri.mjs --input FILE [--input FILE...] [--format text|svg] [--out-dir DIR]
  node benches/compare/tools/kumeyuri.mjs --input FILE --stdout [--format text|svg]

Options:
  --bin FILE         Release kumeyuri binary. Defaults to KUMEYURI_BENCH_BIN or target/release/kumeyuri.
  --format FORMAT    text or svg. Defaults to text.
  --input FILE       Render one corpus file; repeatable.
  --manifest FILE    Render every input listed in a corpus manifest.
  --out-dir DIR      Directory for rendered output and .error.txt files.
  --stdout           Print a single input render to stdout.
  --allow-failures   Exit 0 even when kumeyuri cannot render an input.
`;
}

function takeValue(args, index, flag) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value`);
  return value;
}

function parseArgs(args) {
  const options = {
    bin: process.env.KUMEYURI_BENCH_BIN || defaultBin,
    format: "text",
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
      case "--format":
        options.format = takeValue(args, index, arg);
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
        if (arg.startsWith("--")) throw new Error(`unknown option: ${arg}`);
        options.inputs.push(arg);
        break;
    }
  }
  if (!new Set(["text", "svg"]).has(options.format)) throw new Error("--format must be text or svg");
  if (options.inputs.length > 0) options.manifest = undefined;
  if (options.stdout && options.inputs.length !== 1) throw new Error("--stdout requires exactly one input");
  return options;
}

async function readManifest(manifestPath) {
  const absoluteManifest = resolve(manifestPath);
  const manifest = JSON.parse(await readFile(absoluteManifest, "utf8"));
  if (!Array.isArray(manifest.inputs)) throw new Error(`manifest has no inputs array: ${absoluteManifest}`);
  return manifest.inputs.map((entry) => {
    if (!entry.id || !entry.path) throw new Error(`manifest entry missing id/path: ${JSON.stringify(entry)}`);
    return { id: entry.id, file: resolve(dirname(absoluteManifest), entry.path) };
  });
}

function inputEntries(paths) {
  return paths.map((path) => ({
    id: basename(path).replace(/\.[^.]+$/, ""),
    file: resolve(path),
  }));
}

function errorMessage(error) {
  const stderr = typeof error?.stderr === "string" ? error.stderr.trim() : "";
  const stdout = typeof error?.stdout === "string" ? error.stdout.trim() : "";
  return stderr || stdout || (error instanceof Error ? error.message : String(error));
}

async function renderEntry(entry, options) {
  try {
    const { stdout } = await execFileAsync(options.bin, ["render", entry.file, "--format", options.format], {
      cwd: repoRoot,
      encoding: "utf8",
      maxBuffer: 1024 * 1024 * 128,
    });
    if (options.stdout) {
      process.stdout.write(stdout);
      return { id: entry.id, status: "ok" };
    }
    const extension = options.format === "svg" ? "svg" : "txt";
    const output = join(options.outDir, `${entry.id}.${extension}`);
    await writeFile(output, stdout);
    return { id: entry.id, status: "ok", output };
  } catch (error) {
    const message = errorMessage(error);
    if (options.stdout) {
      process.stderr.write(`${entry.id}: ${message}\n`);
      return { id: entry.id, status: "error", error: message };
    }
    const output = join(options.outDir, `${entry.id}.error.txt`);
    await writeFile(output, `${message}\n`);
    return { id: entry.id, status: "error", error: message, output };
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return 0;
  }
  const entries = options.inputs.length > 0 ? inputEntries(options.inputs) : await readManifest(options.manifest);
  if (!options.stdout) {
    options.outDir = resolve(options.outDir);
    await mkdir(options.outDir, { recursive: true });
  }
  const results = [];
  for (const entry of entries) results.push(await renderEntry(entry, options));
  if (!options.stdout) {
    process.stdout.write(`${JSON.stringify({
      tool: "kumeyuri",
      binary: resolve(options.bin),
      format: options.format,
      results,
    }, null, 2)}\n`);
  }
  return results.some((result) => result.status !== "ok") && !options.allowFailures ? 1 : 0;
}

main().then((exitCode) => {
  process.exitCode = exitCode;
}).catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
