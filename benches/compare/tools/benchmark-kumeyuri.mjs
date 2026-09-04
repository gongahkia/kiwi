#!/usr/bin/env node
import { execFile } from "node:child_process";
import { access, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const defaultManifest = join(repoRoot, "benches/compare/corpus/benchmark-manifest.json");
const defaultProbe = join(repoRoot, "target/release/kumeyuri-bench");
const defaultOut = join(repoRoot, "benches/compare/results/kumeyuri-phases.json");
const operations = ["parse", "layout", "frames", "svg", "kumecast", "raster-gif", "raster-apng", "raster-webp"];
const layoutRoots = new Set(["graph", "flowchart", "sequenceDiagram", "stateDiagram", "stateDiagram-v2"]);

function usage() {
  return `Usage:
  node benches/compare/tools/benchmark-kumeyuri.mjs [--manifest FILE] [--operation NAME] [--iterations N] [--warmup N] [--out FILE]
  node benches/compare/tools/benchmark-kumeyuri.mjs --input FILE [--input FILE...] [--operation NAME]

Options:
  --probe FILE       Release kumeyuri-bench binary. Defaults to KUMEYURI_BENCH_PROBE or target/release/kumeyuri-bench.
  --manifest FILE    Benchmark every entry in a pinned corpus manifest.
  --input FILE       Benchmark one input; repeatable.
  --operation NAME   parse, layout, frames, svg, kumecast, raster-gif, raster-apng, or raster-webp; repeatable. Defaults to all.
  --iterations N     Timed samples collected by the probe. Defaults to 10.
  --warmup N         Unrecorded probe iterations. Defaults to 2.
  --out FILE         JSON report path. Defaults to benches/compare/results/kumeyuri-phases.json.
  --allow-failures   Write errors to the report without returning a nonzero status.
`;
}

function takeValue(args, index, flag) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value`);
  return value;
}

function positiveInteger(value, flag) {
  if (!/^[1-9][0-9]*$/.test(value)) throw new Error(`${flag} must be a positive integer`);
  return Number(value);
}

function parseArgs(args) {
  const options = {
    probe: process.env.KUMEYURI_BENCH_PROBE || defaultProbe,
    manifest: defaultManifest,
    inputs: [],
    operations: [],
    iterations: 10,
    warmup: 2,
    out: defaultOut,
    allowFailures: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--probe":
        options.probe = takeValue(args, index, arg);
        index += 1;
        break;
      case "--manifest":
        options.manifest = takeValue(args, index, arg);
        index += 1;
        break;
      case "--input":
        options.inputs.push(takeValue(args, index, arg));
        index += 1;
        break;
      case "--operation":
        options.operations.push(takeValue(args, index, arg));
        index += 1;
        break;
      case "--iterations":
        options.iterations = positiveInteger(takeValue(args, index, arg), arg);
        index += 1;
        break;
      case "--warmup":
        options.warmup = positiveInteger(takeValue(args, index, arg), arg);
        index += 1;
        break;
      case "--out":
        options.out = takeValue(args, index, arg);
        index += 1;
        break;
      case "--allow-failures":
        options.allowFailures = true;
        break;
      default:
        throw new Error(`unknown option: ${arg}`);
    }
  }
  if (options.inputs.length > 0) options.manifest = undefined;
  if (options.operations.length === 0) options.operations = operations;
  for (const operation of options.operations) {
    if (!operations.includes(operation)) throw new Error(`unknown benchmark operation: ${operation}`);
  }
  return options;
}

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function entriesFromManifest(manifestPath) {
  const absoluteManifest = resolve(manifestPath);
  const manifest = JSON.parse(await readFile(absoluteManifest, "utf8"));
  if (!Array.isArray(manifest.inputs)) throw new Error(`manifest has no inputs array: ${absoluteManifest}`);
  return manifest.inputs.map((entry) => {
    if (!entry.id || !entry.path || !entry.root) throw new Error(`manifest entry missing id/path/root: ${JSON.stringify(entry)}`);
    return { id: entry.id, root: entry.root, file: resolve(dirname(absoluteManifest), entry.path) };
  });
}

async function entriesFromInputs(inputs) {
  return Promise.all(inputs.map(async (input) => ({
    id: input.split("/").at(-1).replace(/\.[^.]+$/, ""),
    root: detectRoot(await readFile(resolve(input), "utf8")),
    file: resolve(input),
  })));
}

function detectRoot(source) {
  for (const rawLine of source.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("%%") || line === "---" || line.startsWith("title:") || line.startsWith("config:")) continue;
    if (line.startsWith("graph ")) return "graph";
    if (line.startsWith("flowchart ")) return "flowchart";
    return line.split(/[\s:]/, 1)[0];
  }
  return "unknown";
}

function percentile(samples, fraction) {
  const sorted = [...samples].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)];
}

async function runProbe(probe, entry, operation, options, workDir) {
  const rssPath = join(workDir, `${entry.id}-${operation}.rss-kib`);
  const { stdout } = await execFileAsync("/usr/bin/time", [
    "-f", "%M",
    "-o", rssPath,
    probe,
    "--input", entry.file,
    "--operation", operation,
    "--iterations", String(options.iterations),
    "--warmup", String(options.warmup),
  ], {
    cwd: repoRoot,
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 16,
  });
  const report = JSON.parse(stdout);
  const samplesMs = report.samplesNs.map((sample) => sample / 1_000_000);
  const peakRssKiB = Number((await readFile(rssPath, "utf8")).trim());
  if (!Number.isFinite(peakRssKiB)) throw new Error(`invalid peak RSS from ${rssPath}`);
  return {
    status: "ok",
    samples: samplesMs.length,
    p50Ms: percentile(samplesMs, 0.5),
    p95Ms: percentile(samplesMs, 0.95),
    minMs: Math.min(...samplesMs),
    maxMs: Math.max(...samplesMs),
    peakRssKiB,
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return 0;
  }
  const probe = resolve(options.probe);
  if (!await exists(probe)) {
    throw new Error(`release benchmark probe not found: ${probe}; run cargo build --release -p kumeyuri-cli --bin kumeyuri-bench`);
  }
  if (!await exists("/usr/bin/time")) throw new Error("/usr/bin/time is required to record peak RSS");

  const entries = options.inputs.length > 0 ? await entriesFromInputs(options.inputs) : await entriesFromManifest(options.manifest);
  const workDir = await mkdtemp(join(tmpdir(), "kumeyuri-bench-"));
  const results = [];
  try {
    for (const entry of entries) {
      const phases = {};
      for (const operation of options.operations) {
        if (operation === "layout" && !layoutRoots.has(entry.root)) {
          phases[operation] = { status: "skipped", reason: "isolated layout probes currently cover flowchart, sequenceDiagram, and stateDiagram roots" };
          continue;
        }
        try {
          phases[operation] = await runProbe(probe, entry, operation, options, workDir);
        } catch (error) {
          phases[operation] = { status: "error", error: error instanceof Error ? error.message : String(error) };
        }
      }
      results.push({ id: entry.id, root: entry.root, input: entry.file, phases });
    }
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }

  const payload = {
    schemaVersion: 1,
    runner: "kumeyuri-bench",
    probe,
    manifest: options.manifest ? resolve(options.manifest) : null,
    iterations: options.iterations,
    warmup: options.warmup,
    results,
  };
  const output = resolve(options.out);
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(payload, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
  const failures = results.some((result) => Object.values(result.phases).some((phase) => phase.status === "error"));
  return failures && !options.allowFailures ? 1 : 0;
}

main().then((exitCode) => {
  process.exitCode = exitCode;
}).catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
