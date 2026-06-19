#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const defaultOutput = "metrics/daily.csv";
const header = "date,github_stars,github_forks,crates_downloads,npm_downloads";

function usage() {
  return `Usage:
  node scripts/poll-daily-metrics.mjs [--output FILE] [--date YYYY-MM-DD]

Environment:
  METRICS_GITHUB_REPO      owner/repo, defaults to GITHUB_REPOSITORY
  METRICS_CRATE            crates.io crate name, defaults to kumeyuri
  METRICS_NPM_PACKAGE      npm package name, defaults to kumeyuri
  GITHUB_TOKEN             optional token for GitHub API rate limit
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
    output: defaultOutput,
    date: today(),
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--output":
        options.output = takeValue(args, index, arg);
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

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      "user-agent": "kumeyuri-metrics",
      "accept": "application/json",
      ...(options.headers ?? {}),
    },
  });
  if (response.status === 404) {
    return undefined;
  }
  if (!response.ok) {
    throw new Error(`${url} returned HTTP ${response.status}`);
  }
  return response.json();
}

async function githubMetrics(repo) {
  if (!repo) return { github_stars: 0, github_forks: 0 };
  const token = process.env.GITHUB_TOKEN;
  const json = await fetchJson(`https://api.github.com/repos/${repo}`, {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  return {
    github_stars: Number(json?.stargazers_count ?? 0),
    github_forks: Number(json?.forks_count ?? 0),
  };
}

async function cratesDownloads(crateName) {
  const json = await fetchJson(`https://crates.io/api/v1/crates/${encodeURIComponent(crateName)}`);
  return Number(json?.crate?.downloads ?? 0);
}

async function npmDownloads(packageName, endDate) {
  const json = await fetchJson(`https://api.npmjs.org/downloads/point/2005-01-01:${endDate}/${encodeURIComponent(packageName)}`);
  return Number(json?.downloads ?? 0);
}

async function existingRows(path) {
  try {
    const text = await readFile(path, "utf8");
    return text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  } catch {
    return [header];
  }
}

function upsertRow(lines, date, metrics) {
  const next = lines[0] === header ? [...lines] : [header, ...lines.slice(1)];
  const row = [
    date,
    metrics.github_stars,
    metrics.github_forks,
    metrics.crates_downloads,
    metrics.npm_downloads,
  ].join(",");
  const index = next.findIndex((line) => line.startsWith(`${date},`));
  if (index >= 1) {
    next[index] = row;
  } else {
    next.push(row);
  }
  return [next[0], ...next.slice(1).sort()].join("\n") + "\n";
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  const repo = process.env.METRICS_GITHUB_REPO || process.env.GITHUB_REPOSITORY || "";
  const crateName = process.env.METRICS_CRATE || "kumeyuri";
  const packageName = process.env.METRICS_NPM_PACKAGE || "kumeyuri";
  const [github, crates, npm] = await Promise.all([
    githubMetrics(repo),
    cratesDownloads(crateName),
    npmDownloads(packageName, options.date),
  ]);
  const metrics = {
    ...github,
    crates_downloads: crates,
    npm_downloads: npm,
  };

  const outputPath = resolve(options.output);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, upsertRow(await existingRows(outputPath), options.date, metrics));
  process.stdout.write(`${JSON.stringify({ date: options.date, ...metrics })}\n`);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
