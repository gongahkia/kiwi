#!/usr/bin/env node
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const defaultInput = "metrics/weekly.csv";
const defaultOutput = "metrics/dashboard.svg";
const numericColumns = [
  "github_stars",
  "github_stars_delta",
  "github_forks",
  "github_forks_delta",
  "crates_downloads",
  "crates_downloads_delta",
  "npm_downloads",
  "npm_downloads_delta",
];

function usage() {
  return `Usage:
  node scripts/generate-metrics-dashboard.mjs [--input FILE] [--output FILE]
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
    output: defaultOutput,
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
      case "--output":
        options.output = takeValue(args, index, arg);
        index += 1;
        break;
      default:
        throw new Error(`unknown option: ${arg}`);
    }
  }
  return options;
}

function parseCsvLine(line) {
  return line.split(",").map((cell) => cell.trim());
}

function parseRows(csv) {
  const lines = csv.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) return [];
  const header = parseCsvLine(lines[0]);
  for (const required of ["week_start", "week_end", ...numericColumns]) {
    if (!header.includes(required)) {
      throw new Error(`missing required column: ${required}`);
    }
  }
  return lines.slice(1).map((line) => {
    const cells = parseCsvLine(line);
    const row = Object.fromEntries(header.map((name, index) => [name, cells[index] ?? ""]));
    for (const column of numericColumns) {
      const value = Number(row[column]);
      if (!Number.isFinite(value)) {
        throw new Error(`invalid numeric value for ${column}: ${row[column]}`);
      }
      row[column] = value;
    }
    return row;
  });
}

function label(text) {
  return text.replace(/["[\]\n\r]/g, " ").replace(/\s+/g, " ").trim();
}

function delta(value) {
  return value >= 0 ? `+${value}` : String(value);
}

function metricLabel(row) {
  return label([
    `${row.week_start} to ${row.week_end}`,
    `stars ${row.github_stars} (${delta(row.github_stars_delta)})`,
    `forks ${row.github_forks} (${delta(row.github_forks_delta)})`,
    `crates ${row.crates_downloads} (${delta(row.crates_downloads_delta)})`,
    `npm ${row.npm_downloads} (${delta(row.npm_downloads_delta)})`,
  ].join(" | "));
}

function dashboardSource(rows) {
  const recent = rows.slice(-8);
  const lines = [
    "flowchart LR",
    '  root["kumeyuri metrics"]',
  ];
  if (recent.length === 0) {
    lines.push('  empty["waiting for first weekly snapshot"]');
    lines.push("  root --> empty");
    return `${lines.join("\n")}\n`;
  }
  recent.forEach((row, index) => {
    const node = `w${index}`;
    lines.push(`  ${node}["${metricLabel(row)}"]`);
    lines.push(`${index === 0 ? "  root" : `  w${index - 1}`} --> ${node}`);
  });
  return `${lines.join("\n")}\n`;
}

async function renderSvg(source) {
  const directory = await mkdtemp(join(tmpdir(), "kumeyuri-metrics-"));
  const sourcePath = join(directory, "dashboard.mmd");
  try {
    await writeFile(sourcePath, source);
    const result = spawnSync("cargo", [
      "run",
      "-q",
      "-p",
      "kumeyuri-cli",
      "--",
      "render",
      sourcePath,
      "--format",
      "svg",
      "--theme",
      "github",
    ], {
      encoding: "utf8",
      maxBuffer: 16 * 1024 * 1024,
    });
    if (result.status !== 0) {
      throw new Error((result.stderr || result.stdout || "kumeyuri render failed").trim());
    }
    return result.stdout;
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  const source = dashboardSource(parseRows(await readFile(options.input, "utf8")));
  const svg = await renderSvg(source);
  const outputPath = resolve(options.output);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, svg.endsWith("\n") ? svg : `${svg}\n`);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
