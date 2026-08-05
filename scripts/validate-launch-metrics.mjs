#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const requiredMetricColumns = [
  "date",
  "github_stars",
  "hosted_searches",
  "extension_installs",
  "slack_installs",
  "mcp_installs",
  "docs_visits"
];

const metricColumns = requiredMetricColumns.filter((column) => column !== "date");

function parseCsv(text) {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  if (lines.length === 0) return { headers: [], rows: [] };
  const headers = lines[0].split(",").map((header) => header.trim());
  const rows = lines.slice(1).map((line) => {
    const values = line.split(",").map((value) => value.trim());
    return Object.fromEntries(headers.map((header, index) => [header, values[index] ?? ""]));
  });
  return { headers, rows };
}

function parseDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function dateDiffDays(a, b) {
  return (b.getTime() - a.getTime()) / 86400000;
}

export function validateLaunchMetrics(text, requiredDays = 14) {
  const { headers, rows } = parseCsv(text);
  const missingColumns = requiredMetricColumns.filter((column) => !headers.includes(column));
  const errors = [];
  if (rows.length < requiredDays) errors.push(`expected at least ${requiredDays} daily rows`);
  for (const column of missingColumns) errors.push(`missing column: ${column}`);

  let previousDate = null;
  rows.forEach((row, index) => {
    const rowNumber = index + 2;
    const date = parseDate(row.date ?? "");
    if (!date) {
      errors.push(`row ${rowNumber}: invalid date`);
    } else if (previousDate && dateDiffDays(previousDate, date) !== 1) {
      errors.push(`row ${rowNumber}: date is not consecutive`);
    }
    previousDate = date;

    for (const column of metricColumns) {
      const value = row[column];
      if (!/^\d+$/.test(value ?? "")) {
        errors.push(`row ${rowNumber}: ${column} must be a non-negative integer`);
      }
    }
  });

  return {
    errors,
    ok: errors.length === 0,
    rows: rows.length
  };
}

function main() {
  const path = process.argv[2];
  if (!path) {
    console.error("usage: pnpm launch:metrics:check -- reports/launch/launch-metrics.csv");
    process.exit(1);
  }

  const result = validateLaunchMetrics(readFileSync(path, "utf8"));
  if (!result.ok) {
    for (const error of result.errors) console.error(error);
    process.exit(1);
  }
  console.log(`launch metrics ok: ${path} (${result.rows} rows)`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
