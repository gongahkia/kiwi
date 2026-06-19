#!/usr/bin/env node
import { execFile } from "node:child_process";
import { access, mkdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const defaultInput = join(repoRoot, "benches/compare/corpus/flowchart-dense.mmd");
const defaultOut = join(repoRoot, "benches/compare/results/timing.json");
const defaultResultsDir = join(repoRoot, "benches/compare/results/timing");

function usage() {
  return `Usage:
  node benches/compare/tools/run-hyperfine.mjs [--input FILE] [--out FILE] [--runs N]

Options:
  --input FILE   Corpus input to benchmark. Defaults to flowchart-dense.mmd.
  --out FILE     hyperfine JSON export path. Defaults to benches/compare/results/timing.json.
  --runs N       Exact hyperfine runs per command. Defaults to 3.
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
    input: defaultInput,
    out: defaultOut,
    runs: "3",
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
      case "--out":
        options.out = takeValue(args, index, arg);
        index += 1;
        break;
      case "--runs":
        options.runs = takeValue(args, index, arg);
        index += 1;
        break;
      default:
        throw new Error(`unknown option: ${arg}`);
    }
  }

  if (!/^[1-9][0-9]*$/.test(options.runs)) {
    throw new Error("--runs must be a positive integer");
  }
  return options;
}

async function executableExists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function pathBinary(name) {
  try {
    const { stdout } = await execFileAsync("command", ["-v", name], { shell: true });
    return stdout.trim();
  } catch {
    return "";
  }
}

async function adapterCommands(options) {
  const input = resolve(options.input);
  const node = process.execPath;
  const commands = [
    {
      name: "beautiful-mermaid",
      command: `${node} benches/compare/tools/beautiful-mermaid.mjs --input ${JSON.stringify(input)} --out-dir ${JSON.stringify(join(defaultResultsDir, "beautiful-mermaid"))}`,
    },
    {
      name: "mermaid2term",
      command: `${node} benches/compare/tools/mermaid2term.mjs --input ${JSON.stringify(input)} --out-dir ${JSON.stringify(join(defaultResultsDir, "mermaid2term"))}`,
    },
    {
      name: "mermaid-cli",
      command: `${node} benches/compare/tools/mermaid-cli.mjs --input ${JSON.stringify(input)} --out-dir ${JSON.stringify(join(defaultResultsDir, "mermaid-cli"))}`,
    },
  ];

  const alexanderBin = process.env.MERMAID_ASCII_BIN || await pathBinary("mermaid-ascii");
  if (alexanderBin && await executableExists(alexanderBin)) {
    commands.push({
      name: "alexander-mermaid-ascii",
      command: `${node} benches/compare/tools/alexander-mermaid-ascii.mjs --bin ${JSON.stringify(alexanderBin)} --input ${JSON.stringify(input)} --out-dir ${JSON.stringify(join(defaultResultsDir, "alexander-mermaid-ascii"))}`,
    });
  }

  const pgavlinBin = process.env.PGAVLIN_MERMAID_ASCII_BIN || "";
  if (pgavlinBin && await executableExists(pgavlinBin)) {
    commands.push({
      name: "pgavlin-mermaid-ascii",
      command: `${node} benches/compare/tools/pgavlin-mermaid-ascii.mjs --bin ${JSON.stringify(pgavlinBin)} --input ${JSON.stringify(input)} --out-dir ${JSON.stringify(join(defaultResultsDir, "pgavlin-mermaid-ascii"))}`,
    });
  }

  return commands;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  const out = resolve(options.out);
  await mkdir(dirname(out), { recursive: true });
  await mkdir(defaultResultsDir, { recursive: true });

  const commands = await adapterCommands(options);
  if (commands.length === 0) {
    throw new Error("no benchmark commands available");
  }

  const args = [
    "--warmup",
    "0",
    "--runs",
    options.runs,
    "--export-json",
    out,
    "--ignore-failure",
  ];
  for (const entry of commands) {
    args.push("--command-name", entry.name);
  }
  args.push(...commands.map((entry) => entry.command));

  await execFileAsync("hyperfine", args, {
    cwd: repoRoot,
    maxBuffer: 1024 * 1024 * 16,
  });
  process.stdout.write(`${JSON.stringify({
    output: out,
    commands: commands.map((entry) => entry.name),
  }, null, 2)}\n`);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
