import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const root = resolve(dirname(scriptPath), "..");
const manifestPath = join(root, "tests/fuzz/official-mermaid/manifest.json");
const compatPath = join(root, "site/compat.json");
const defaultOutput = join(root, "site/motion.json");
const maxBuffer = 64 * 1024 * 1024;

const args = new Set(process.argv.slice(2));
if (args.has("--help")) {
  console.log("usage: node scripts/check-animation-quality.mjs [--write] [--check] [--out FILE]");
  process.exit(0);
}

const outputPath = argValue("--out") ? resolve(root, argValue("--out")) : defaultOutput;
for (const arg of process.argv.slice(2)) {
  if (arg === "--write" || arg === "--check" || arg === "--out" || argValue("--out") === arg) {
    continue;
  }
  console.error(`unknown argument: ${arg}`);
  process.exit(2);
}

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const compat = JSON.parse(readFileSync(compatPath, "utf8"));
const report = buildReport(manifest, compat);
const text = `${JSON.stringify(report, null, 2)}\n`;

if (args.has("--write")) {
  writeFileSync(outputPath, text);
  console.log(`wrote ${relative(outputPath)}`);
} else if (args.has("--check")) {
  const current = readFileSync(outputPath, "utf8");
  if (current !== text) {
    console.error(`${relative(outputPath)} drifted from animation quality gate`);
    process.exit(1);
  }
  console.log("animation quality report ok");
} else {
  process.stdout.write(text);
}

const failures = report.families.filter((family) => family.failures.length);
if (failures.length) {
  console.error(`animation quality failures: ${failures.map((family) => family.rootType).join(", ")}`);
  process.exit(1);
}

function buildReport(manifest, compat) {
  const families = manifest.fixtures.map((fixture) => analyzeFixture(fixture, compat));
  return {
    schemaVersion: 1,
    generatedBy: "scripts/check-animation-quality.mjs",
    mermaidVersion: manifest.mermaidVersion,
    checks: [
      "animated roots produce at least two frames",
      "static-only roots collapse to exactly one frame",
      "animated SVG contains motion timing",
      "all SVG output contains prefers-reduced-motion CSS",
      "frame durations are positive",
    ],
    counts: {
      families: families.length,
      animatedPartial: families.filter((family) => family.support === "animated-partial").length,
      staticOnlyPartial: families.filter((family) => family.support === "static-only-partial").length,
      failures: families.filter((family) => family.failures.length).length,
    },
    families,
  };
}

function analyzeFixture(fixture, compat) {
  const source = readFileSync(join(root, fixture.fixturePath), "utf8");
  const rootType = detectRoot(source) ?? fixture.rootType;
  const support = supportForRoot(compat, rootType);
  const svg = runKumeyuri(["render", fixture.fixturePath, "--format", "svg"]).stdout;
  const cast = JSON.parse(runKumeyuri(["export", fixture.fixturePath, "--format", "kumecast"]).stdout);
  const durations = cast.timeline.frames.map((frame) => frame.durationMs);
  const frames = durations.length;
  const failures = [];
  if (support === "animated-partial" && frames < 2) {
    failures.push("animated root produced fewer than two frames");
  }
  if (support === "static-only-partial" && frames !== 1) {
    failures.push("static-only root produced more than one frame");
  }
  if (support === "animated-partial" && !svg.includes("<animate") && !svg.includes("@keyframes")) {
    failures.push("animated root SVG has no SMIL or CSS keyframes");
  }
  if (!svg.includes("prefers-reduced-motion: reduce")) {
    failures.push("SVG missing reduced-motion CSS");
  }
  if (durations.some((duration) => !Number.isFinite(duration) || duration <= 0)) {
    failures.push("timeline contains non-positive frame duration");
  }
  return {
    fixturePath: fixture.fixturePath,
    rootType,
    support,
    intent: animationIntent(rootType, support),
    frames,
    totalDurationMs: durations.reduce((total, duration) => total + duration, 0),
    minFrameDurationMs: Math.min(...durations),
    maxFrameDurationMs: Math.max(...durations),
    reducedMotionCss: svg.includes("prefers-reduced-motion: reduce"),
    svgAnimation: svg.includes("<animate") ? "smil" : svg.includes("@keyframes") ? "css-keyframes" : "none",
    failures,
  };
}

function runKumeyuri(args) {
  try {
    const stdout = process.env.KUMEYURI_BIN
      ? execFileSync(process.env.KUMEYURI_BIN, args, { cwd: root, encoding: "utf8", maxBuffer })
      : execFileSync("cargo", ["run", "-q", "-p", "kumeyuri-cli", "--", ...args], {
          cwd: root,
          encoding: "utf8",
          maxBuffer,
        });
    return { stdout };
  } catch (error) {
    throw new Error(String(error.stderr || error.stdout || error.message || error));
  }
}

function supportForRoot(compat, rootType) {
  const entry = compat.roots.find((candidate) => candidate.roots.includes(rootType));
  return entry?.support ?? "unsupported";
}

function detectRoot(source) {
  for (const rawLine of source.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("%%") || line === "---" || line.startsWith("title:") || line.startsWith("config:")) {
      continue;
    }
    if (line.startsWith("graph ")) {
      return "graph";
    }
    if (line.startsWith("flowchart ")) {
      return "flowchart";
    }
    return line.split(/[\s:]/, 1)[0];
  }
  return undefined;
}

function animationIntent(rootType, support) {
  if (support === "static-only-partial") {
    return "render deterministic schematic static frame";
  }
  if (rootType === "sequenceDiagram") {
    return "play messages over participant lanes";
  }
  if (rootType === "stateDiagram" || rootType === "stateDiagram-v2") {
    return "step through state transitions";
  }
  if (rootType === "gantt") {
    return "trace scheduled work over a day-level timeline";
  }
  if (rootType === "pie") {
    return "reveal slices and value proportions";
  }
  return "reveal structure in source or dependency order";
}

function argValue(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return process.argv[index + 1];
}

function relative(filePath) {
  return filePath.startsWith(root) ? filePath.slice(root.length + 1) : filePath;
}
