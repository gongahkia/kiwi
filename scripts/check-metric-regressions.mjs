import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const metricFiles = (process.env.PERF_GATE_FILES ?? "bench/perf-baseline.json")
  .split(",")
  .map((file) => file.trim())
  .filter(Boolean);
const threshold = Number(process.env.PERF_GATE_THRESHOLD ?? "0.10");
const base = resolveBaseRevision();
const head = resolveHeadRevision();
const labels = (process.env.PERF_GATE_LABELS ?? "")
  .split(",")
  .map((label) => label.trim())
  .filter(Boolean);

if (!Number.isFinite(threshold) || threshold <= 0) {
  throw new Error("PERF_GATE_THRESHOLD must be a positive number");
}

if (labels.some((label) => label.startsWith("perf:"))) {
  console.log(`Performance regression gate bypassed by label: ${labels.find((label) => label.startsWith("perf:"))}`);
  process.exit(0);
}

if (!base) {
  console.log("No performance gate base revision; skipping metric regression check.");
  process.exit(0);
}

const regressions = [];
for (const file of metricFiles) {
  const oldMetrics = metricsAtRevision(base, file);
  const newMetrics = metricsAtRevision(head, file);
  if (!oldMetrics || !newMetrics) {
    continue;
  }
  for (const [name, current] of Object.entries(newMetrics.metrics ?? {})) {
    const previous = oldMetrics.metrics?.[name];
    if (!previous) {
      continue;
    }
    const regression = metricRegression(name, previous, current, threshold);
    if (regression) {
      regressions.push(`${file}: ${regression}`);
    }
  }
}

if (regressions.length > 0) {
  console.error(
    [
      `Performance regression gate failed (> ${(threshold * 100).toFixed(0)}% without perf: label).`,
      "",
      ...regressions.map((regression) => `- ${regression}`),
    ].join("\n"),
  );
  process.exit(1);
}

console.log("Performance regression gate passed.");

function metricRegression(name, previous, current, threshold) {
  const oldValue = Number(previous.value);
  const newValue = Number(current.value);
  if (!Number.isFinite(oldValue) || !Number.isFinite(newValue) || oldValue <= 0) {
    return null;
  }

  const direction = current.direction ?? previous.direction;
  if (direction === "lower-is-better") {
    const limit = oldValue * (1 + threshold);
    if (newValue > limit) {
      return `${name}: ${oldValue} -> ${newValue} (${percentChange(oldValue, newValue)} worse)`;
    }
    return null;
  }
  if (direction === "higher-is-better") {
    const limit = oldValue * (1 - threshold);
    if (newValue < limit) {
      return `${name}: ${oldValue} -> ${newValue} (${percentChange(oldValue, newValue)} worse)`;
    }
    return null;
  }
  return null;
}

function percentChange(oldValue, newValue) {
  return `${(((newValue - oldValue) / oldValue) * 100).toFixed(1)}%`;
}

function metricsAtRevision(revision, file) {
  try {
    const content = revision === "HEAD" ? readFileSync(file, "utf8") : git(["show", `${revision}:${file}`]);
    return JSON.parse(content);
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw error;
    }
    return null;
  }
}

function resolveBaseRevision() {
  const explicit = process.env.PERF_GATE_BASE;
  if (explicit && !allZeros(explicit) && revExists(explicit)) {
    return explicit;
  }
  const githubBase = process.env.GITHUB_BASE_REF;
  if (githubBase) {
    const mergeBase = git(["merge-base", "HEAD", `origin/${githubBase}`], { allowFailure: true });
    if (mergeBase.trim()) {
      return mergeBase.trim();
    }
  }
  if (revExists("HEAD~1")) {
    return "HEAD~1";
  }
  return null;
}

function resolveHeadRevision() {
  const explicit = process.env.PERF_GATE_HEAD;
  if (explicit && !allZeros(explicit) && revExists(explicit)) {
    return explicit;
  }
  return "HEAD";
}

function revExists(revision) {
  return spawnSync("git", ["rev-parse", "--verify", `${revision}^{commit}`], {
    encoding: "utf8",
  }).status === 0;
}

function allZeros(value) {
  return value.length > 0 && Array.from(value).every((char) => char === "0");
}

function git(args, options = {}) {
  const result = spawnSync("git", args, { encoding: "utf8" });
  if (result.status !== 0 && !options.allowFailure) {
    throw new Error(result.stderr.trim() || `git ${args.join(" ")} failed`);
  }
  return result.stdout;
}
