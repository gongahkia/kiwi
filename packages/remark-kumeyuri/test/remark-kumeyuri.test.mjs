import assert from "node:assert/strict";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import remarkKumeyuri from "../index.js";

const dir = await mkdtemp(path.join(tmpdir(), "remark-kumeyuri-test-"));
try {
  const fake = path.join(dir, "kumeyuri");
  await writeFile(fake, `#!/usr/bin/env node
const format = process.argv[process.argv.indexOf("--format") + 1]
process.stdout.write(format === "svg" ? "<svg data-test=\\"kumeyuri\\"></svg>\\n" : "rendered text\\n")
`, "utf8");
  await chmod(fake, 0o755);

  const tree = rootWithMermaid();
  await remarkKumeyuri({ kumeyuri: fake, format: "text" })(tree);
  assert.equal(tree.children.length, 3);
  assert.equal(tree.children[1].type, "code");
  assert.equal(tree.children[1].lang, "text");
  assert.equal(tree.children[1].value, "rendered text");
  assert.equal(tree.children[2].lang, "js");

  const svgTree = rootWithMermaid();
  await remarkKumeyuri({ kumeyuri: fake, format: "svg", replace: true })(svgTree);
  assert.equal(svgTree.children.length, 2);
  assert.equal(svgTree.children[0].type, "html");
  assert.match(svgTree.children[0].value, /<svg/);
  assert.equal(svgTree.children[1].lang, "js");
} finally {
  await rm(dir, { recursive: true, force: true });
}

function rootWithMermaid() {
  return {
    type: "root",
    children: [
      {
        type: "code",
        lang: "mermaid",
        meta: null,
        value: "graph TD\nA --> B",
      },
      {
        type: "code",
        lang: "js",
        meta: null,
        value: "console.log('skip')",
      },
    ],
  };
}

console.log("ok");
