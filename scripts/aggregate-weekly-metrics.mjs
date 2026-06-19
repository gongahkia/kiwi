#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const defaultInput = "metrics/daily.csv";
const defaultOutput = "metrics/weekly.csv";
const outputHeader = [
  "week_start",
  "week_end",
  "github_stars",
  "github_stars_delta",
  "github_forks",
  "github_forks_delta",
  "crates_downloads",
  "crates_downloads_delta",
  "npm_downloads",
  "npm_downloads_delta",
];
const metricColumns = [
  "github_stars",
  "github_forks",
  "crates_downloads",
  "npm_downloads",
];

function usage() {
  return `Usage:
  node scripts/aggregate-weekly-metrics.mjs [--input FILE] [--output FILE]

Input schema:
  date,github_stars,github_forks,crates_downloads,npm_downloads
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

function formatDate(date) {
  return date.toISOString().slice(0, 10);
}

function weekStart(dateText) {
  const date = new Date(`${dateText}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`invalid date: ${dateText}`);
  }
  const day = date.getUTCDay();
  const mondayOffset = day === 0 ? -6 : 1 - day;
  date.setUTCDate(date.getUTCDate() + mondayOffset);
  return formatDate(date);
}

function parseRows(csv) {
  const lines = csv.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) return [];
  const header = parseCsvLine(lines[0]);
  for (const required of ["date", ...metricColumns]) {
    if (!header.includes(required)) {
      throw new Error(`missing required column: ${required}`);
    }
  }

  return lines.slice(1).map((line) => {
    const cells = parseCsvLine(line);
    const row = Object.fromEntries(header.map((name, index) => [name, cells[index] ?? ""]));
    for (const column of metricColumns) {
      const value = Number(row[column]);
      if (!Number.isFinite(value)) {
        throw new Error(`invalid numeric value for ${column}: ${row[column]}`);
      }
      row[column] = value;
    }
    row.week_start = weekStart(row.date);
    return row;
  }).sort((a, b) => a.date.localeCompare(b.date));
}

function aggregateWeekly(rows) {
  const groups = new Map();
  for (const row of rows) {
    if (!groups.has(row.week_start)) {
      groups.set(row.week_start, []);
    }
    groups.get(row.week_start).push(row);
  }

  return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([start, weekRows]) => {
    const first = weekRows[0];
    const last = weekRows[weekRows.length - 1];
    const output = {
      week_start: start,
      week_end: last.date,
    };
    for (const column of metricColumns) {
      output[column] = last[column];
      output[`${column}_delta`] = last[column] - first[column];
    }
    return output;
  });
}

function serializeRows(rows) {
  return [
    outputHeader.join(","),
    ...rows.map((row) => outputHeader.map((column) => row[column]).join(",")),
  ].join("\n") + "\n";
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  const rows = aggregateWeekly(parseRows(await readFile(options.input, "utf8")));
  const outputPath = resolve(options.output);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, serializeRows(rows));
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
