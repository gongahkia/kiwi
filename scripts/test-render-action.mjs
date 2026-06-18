import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";

const repoRoot = resolve(new URL("..", import.meta.url).pathname);
const temp = mkdtempSync(join(tmpdir(), "kumeyuri-render-action-"));

try {
  mkdirSync(join(temp, "diagrams", "nested"), { recursive: true });
  writeFileSync(join(temp, "diagrams", "flow.mmd"), "graph TD\nA --> B\n");
  writeFileSync(join(temp, "diagrams", "nested", "state.mmd"), "stateDiagram-v2\n[*] --> A\n");

  const fake = join(temp, "fake-kumeyuri.mjs");
  writeFileSync(
    fake,
    [
      "const args = process.argv.slice(2);",
      "if (args[0] !== 'render') process.exit(2);",
      "const file = args[1];",
      "const format = args[args.indexOf('--format') + 1];",
      "process.stdout.write(`${format}:${file}`);",
    ].join("\n"),
  );

  const outputFile = join(temp, "github-output.txt");
  const result = spawnSync("node", [join(repoRoot, "render-action", "render.mjs")], {
    cwd: temp,
    encoding: "utf8",
    env: {
      ...process.env,
      GITHUB_WORKSPACE: temp,
      GITHUB_OUTPUT: outputFile,
      INPUT_SOURCE: "diagrams/**/*.mmd",
      INPUT_OUTPUT_DIR: "rendered",
      INPUT_FORMATS: "svg,gif",
      INPUT_KUMEYURI_COMMAND: `node ${fake}`,
      INPUT_THEME: "github",
      INPUT_PADDING: "2",
      INPUT_FAIL_ON_EMPTY: "true",
    },
  });

  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }

  assertFile(join(temp, "rendered", "diagrams", "flow.svg"), "svg:");
  assertFile(join(temp, "rendered", "diagrams", "flow.gif"), "gif:");
  assertFile(join(temp, "rendered", "diagrams", "nested", "state.svg"), "svg:");
  assertFile(join(temp, "rendered", "diagrams", "nested", "state.gif"), "gif:");
  assertFile(outputFile, "file-count=2");
  assertFile(outputFile, "rendered-count=4");
  console.log("render action harness passed");
} finally {
  rmSync(temp, { recursive: true, force: true });
}

function assertFile(path, expected) {
  const content = readFileSync(path, "utf8");
  if (!content.includes(expected)) {
    throw new Error(`${path} did not include ${expected}`);
  }
}
