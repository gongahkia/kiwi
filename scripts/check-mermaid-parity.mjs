import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const root = resolve(dirname(scriptPath), "..");
const manifestPath = join(root, "tests/fuzz/official-mermaid/manifest.json");
const defaultOutput = join(root, "site/parity.json");
const defaultKumeyuriBin = "target/debug/kumeyuri";
const maxBuffer = 64 * 1024 * 1024;

const args = new Set(process.argv.slice(2));
if (args.has("--help")) {
  console.log("usage: node scripts/check-mermaid-parity.mjs [--write] [--check] [--skip-mermaid] [--require-mermaid] [--out FILE]");
  process.exit(0);
}

const outputPath = argValue("--out") ? resolve(root, argValue("--out")) : defaultOutput;
const write = args.has("--write");
const check = args.has("--check");
const skipMermaid = args.has("--skip-mermaid");
const requireMermaid = args.has("--require-mermaid");

for (const arg of process.argv.slice(2)) {
  if (arg === "--write" || arg === "--check" || arg === "--skip-mermaid" || arg === "--require-mermaid") {
    continue;
  }
  if (arg === "--out" || argValue("--out") === arg) {
    continue;
  }
  console.error(`unknown argument: ${arg}`);
  process.exit(2);
}

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const compat = loadCompat();
const report = buildReport(manifest, compat);
const text = `${JSON.stringify(report, null, 2)}\n`;

if (write) {
  writeFileSync(outputPath, text);
  console.log(`wrote ${relative(outputPath)}`);
} else if (check) {
  const current = readFileSync(outputPath, "utf8");
  if (current !== text) {
    console.error(`${relative(outputPath)} drifted from Mermaid parity harness`);
    process.exit(1);
  }
  console.log("Mermaid parity report ok");
} else {
  process.stdout.write(text);
}

const failures = report.fixtures.filter((fixture) => {
  if (!fixture.kumeyuri.parseOk || !fixture.kumeyuri.renderOk) {
    return true;
  }
  return requireMermaid && fixture.mermaid.status !== "rendered";
});
if (failures.length) {
  console.error(`Mermaid parity failures: ${failures.map((fixture) => fixture.fixturePath).join(", ")}`);
  process.exit(1);
}

function buildReport(manifest, compat) {
  const tmp = mkdtempSync(join(tmpdir(), "kumeyuri-parity-"));
  try {
    const fixtures = manifest.fixtures.map((fixture, index) => analyzeFixture(fixture, index, tmp, compat));
    return {
      schemaVersion: 1,
      generatedBy: "scripts/check-mermaid-parity.mjs",
      mermaidVersion: manifest.mermaidVersion,
      sources: {
        fixtures: "tests/fuzz/official-mermaid/manifest.json",
        kumeyuri: "kumeyuri-cli",
        mermaid: skipMermaid ? "skipped" : "npx mmdc",
      },
      counts: {
        fixtures: fixtures.length,
        kumeyuriParsed: fixtures.filter((fixture) => fixture.kumeyuri.parseOk).length,
        kumeyuriRendered: fixtures.filter((fixture) => fixture.kumeyuri.renderOk).length,
        mermaidRendered: fixtures.filter((fixture) => fixture.mermaid.status === "rendered").length,
        animatedPartial: fixtures.filter((fixture) => fixture.kumeyuri.animationSupport === "animated-partial").length,
        staticOnlyPartial: fixtures.filter((fixture) => fixture.kumeyuri.animationSupport === "static-only-partial").length,
        unsupported: fixtures.filter((fixture) => fixture.kumeyuri.animationSupport === "unsupported").length,
        deltas: fixtures.reduce((total, fixture) => total + fixture.deltas.length, 0),
      },
      fixtures,
    };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function analyzeFixture(fixture, index, tmp, compat) {
  const fixturePath = join(root, fixture.fixturePath);
  const source = readFileSync(fixturePath, "utf8");
  const rootType = detectRoot(source) ?? fixture.rootType;
  const support = supportForRoot(compat, rootType);
  const kumeyuri = runKumeyuriFixture(fixture.fixturePath, support);
  const mermaid = skipMermaid ? { status: "skipped", error: null } : runMermaidFixture(fixturePath, index, tmp);
  const deltas = [];
  if (fixture.expectedParserStatus === "pass" && !kumeyuri.parseOk) {
    deltas.push("kumeyuri-parse-failed");
  }
  if (fixture.expectedRenderStatus === "pass" && !kumeyuri.renderOk) {
    deltas.push("kumeyuri-render-failed");
  }
  if (mermaid.status !== "rendered" && !skipMermaid) {
    deltas.push("mermaid-render-failed");
  }
  if (support === "animated-partial" && kumeyuri.frames < 2) {
    deltas.push("animated-root-static-output");
  }
  if (support === "static-only-partial" && kumeyuri.frames !== 1) {
    deltas.push("static-only-root-animated-output");
  }
  return {
    fixturePath: fixture.fixturePath,
    sourceUrl: fixture.sourceUrl,
    rootType,
    expectedParserStatus: fixture.expectedParserStatus,
    expectedRenderStatus: fixture.expectedRenderStatus,
    kumeyuri,
    mermaid,
    deltas,
  };
}

function runKumeyuriFixture(fixturePath, support) {
  const render = runKumeyuri(["render", fixturePath, "--format", "svg"]);
  if (!render.ok) {
    return {
      parseOk: false,
      renderOk: false,
      frames: 0,
      animationSupport: support,
      svgBytes: 0,
      error: render.error,
    };
  }
  const cast = runKumeyuri(["export", fixturePath, "--format", "kumecast"]);
  const frames = cast.ok ? JSON.parse(cast.stdout).timeline.frames.length : 0;
  return {
    parseOk: true,
    renderOk: render.stdout.includes("<svg") && render.stdout.includes("</svg>"),
    frames,
    animationSupport: support,
    svgBytes: Buffer.byteLength(render.stdout),
    error: cast.ok ? null : cast.error,
  };
}

function runMermaidFixture(inputPath, index, tmp) {
  const outputPath = join(tmp, `${String(index).padStart(2, "0")}.svg`);
  try {
    execFileSync("npx", ["mmdc", "-i", inputPath, "-o", outputPath], {
      cwd: root,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer,
    });
    const svg = readFileSync(outputPath, "utf8");
    return {
      status: svg.includes("<svg") ? "rendered" : "invalid-output",
      error: null,
    };
  } catch (error) {
    return {
      status: "failed",
      error: cleanError(error),
    };
  }
}

function runKumeyuri(args) {
  try {
    const kumeyuriBin = process.env.KUMEYURI_BIN ?? (existsSync(join(root, defaultKumeyuriBin)) ? defaultKumeyuriBin : undefined);
    const stdout = kumeyuriBin
      ? execFileSync(kumeyuriBin, args, { cwd: root, encoding: "utf8", maxBuffer })
      : execFileSync("cargo", ["run", "-q", "-p", "kumeyuri-cli", "--", ...args], {
          cwd: root,
          encoding: "utf8",
          maxBuffer,
        });
    return { ok: true, stdout };
  } catch (error) {
    return { ok: false, stdout: error.stdout ?? "", error: cleanError(error) };
  }
}

function loadCompat() {
  try {
    return JSON.parse(readFileSync(join(root, "site/compat.json"), "utf8"));
  } catch {
    return JSON.parse(runKumeyuri(["compat", "--json"]).stdout);
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

function cleanError(error) {
  return String(error.stderr || error.stdout || error.message || error)
    .replaceAll(root, "<repo>")
    .replaceAll(root.replaceAll("/", "%2F"), "%3Crepo%3E")
    .split(/\r?\n/)
    .filter(Boolean)
    .slice(0, 8)
    .join("\n");
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
